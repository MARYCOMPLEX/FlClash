// 自定义功能：每日 / 按域名 的流量统计（FlClash fork 注入模块）
//
// 数据来源：内核通过 CoreEventType.requestTraffic 推送的每条连接 upload/download 增量，
//          配合 CoreEventType.request 推送的连接元信息（host / process / chains）。
// 存储：homeDir/traffic_stats.json，按天聚合，保留 90 天。
// 查看：内置 http 服务 http://127.0.0.1:18999

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:path/path.dart' as p;

class _ConnMeta {
  _ConnMeta(this.host, this.process, this.exit);

  final String host;
  final String process;
  final String exit;
}

class _Bucket {
  final Map<String, List<int>> domains = <String, List<int>>{};
  final Map<String, List<int>> procs = <String, List<int>>{};
  final Map<String, List<int>> exits = <String, List<int>>{};

  void add(Map<String, List<int>> map, String key, int up, int down) {
    final value = map[key];
    if (value == null) {
      map[key] = <int>[up, down];
    } else {
      value[0] += up;
      value[1] += down;
    }
  }

  Map<String, Object> toJson() => <String, Object>{
    'domains': domains,
    'procs': procs,
    'exits': exits,
  };

  static _Bucket fromJson(Map<String, Object?> json) {
    final bucket = _Bucket();
    void load(Map<String, List<int>> target, Object? raw) {
      if (raw is! Map) {
        return;
      }
      raw.forEach((key, value) {
        if (value is List && value.length >= 2) {
          target['$key'] = <int>[
            (value[0] as num).toInt(),
            (value[1] as num).toInt(),
          ];
        }
      });
    }

    load(bucket.domains, json['domains']);
    load(bucket.procs, json['procs']);
    load(bucket.exits, json['exits']);
    return bucket;
  }
}

class TrafficStats with CoreEventListener {
  TrafficStats._();

  static final TrafficStats instance = TrafficStats._();

  static const int port = 18999;
  static const int keepDays = 90;

  final Map<String, _ConnMeta> _conns = <String, _ConnMeta>{};
  final Map<String, Map<String, int>> _last = <String, Map<String, int>>{};
  final Map<String, _Bucket> _days = <String, _Bucket>{};

  File? _file;
  HttpServer? _server;
  Timer? _timer;
  bool _dirty = false;
  int _live = 0;

  static String _dayKey([DateTime? time]) {
    final value = time ?? DateTime.now();
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static Future<void> start() async {
    try {
      await instance._start();
    } catch (error) {
      commonPrint.log(
        'traffic stats start failed: $error',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<void> _start() async {
    final home = await appPath.homeDirPath;
    _file = File(p.join(home, 'traffic_stats.json'));
    await _load();
    coreEventManager.addListener(this);
    _startServer();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _flush());
    commonPrint.log('traffic stats started on 127.0.0.1:$port');
  }

  Future<void> _load() async {
    final file = _file;
    if (file == null || !await file.exists()) {
      return;
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) {
        return;
      }
      final days = raw['days'];
      if (days is Map) {
        days.forEach((key, value) {
          if (value is Map) {
            _days['$key'] = _Bucket.fromJson(Map<String, Object?>.from(value));
          }
        });
      }
    } catch (error) {
      commonPrint.log('traffic stats load failed: $error', logLevel: LogLevel.warning);
    }
  }

  Future<void> _flush() async {
    if (!_dirty) {
      return;
    }
    final file = _file;
    if (file == null) {
      return;
    }
    _dirty = false;
    _prune();
    try {
      final payload = <String, Object>{
        'version': 1,
        'updated': DateTime.now().toIso8601String(),
        'days': <String, Object>{
          for (final entry in _days.entries) entry.key: entry.value.toJson(),
        },
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (error) {
      commonPrint.log('traffic stats save failed: $error', logLevel: LogLevel.warning);
    }
  }

  void _prune() {
    final keys = _days.keys.toList()..sort();
    while (keys.length > keepDays) {
      _days.remove(keys.removeAt(0));
    }
  }

  _Bucket _today() {
    final key = _dayKey();
    return _days.putIfAbsent(key, () => _Bucket());
  }

  @override
  void onRequest(TrackerInfo connection) {
    final metadata = connection.metadata;
    final host = metadata.host.isNotEmpty ? metadata.host : metadata.destinationIP;
    final chains = connection.chains;
    _conns[connection.id] = _ConnMeta(
      host.isEmpty ? '(unknown)' : host,
      metadata.process.isEmpty ? 'unknown' : metadata.process,
      chains.isEmpty ? 'DIRECT' : chains.first,
    );
  }

  @override
  void onRequestTraffic(Map<String, RequestTraffic> traffic) {
    _live = traffic.length;
    if (traffic.isEmpty) {
      return;
    }
    final bucket = _today();
    var changed = false;
    for (final entry in traffic.entries) {
      final current = <String, int>{
        'up': entry.value.upload,
        'down': entry.value.download,
      };
      final previous = _last[entry.key];
      _last[entry.key] = current;
      if (previous == null) {
        continue;
      }
      final up = current['up']! - previous['up']!;
      final down = current['down']! - previous['down']!;
      if (up <= 0 && down <= 0) {
        continue;
      }
      final meta = _conns[entry.key];
      final host = meta?.host ?? '(closed)';
      final process = meta?.process ?? 'unknown';
      final exit = meta?.exit ?? 'DIRECT';
      bucket.add(bucket.domains, host, up > 0 ? up : 0, down > 0 ? down : 0);
      bucket.add(bucket.procs, process, up > 0 ? up : 0, down > 0 ? down : 0);
      bucket.add(bucket.exits, exit, up > 0 ? up : 0, down > 0 ? down : 0);
      changed = true;
    }
    if (changed) {
      _dirty = true;
    }
    if (_last.length > 2000) {
      final alive = traffic.keys.toSet();
      _last.removeWhere((key, _) => !alive.contains(key));
      _conns.removeWhere((key, _) => !alive.contains(key));
    }
  }

  String _snapshot() {
    final days = <String, Object>{
      for (final entry in _days.entries) entry.key: entry.value.toJson(),
    };
    return jsonEncode(<String, Object>{
      'today': _dayKey(),
      'live': _live,
      'days': days,
    });
  }

  void _startServer() {
    HttpServer.bind(InternetAddress.loopbackIPv4, port).then((server) {
      _server = server;
      server.listen((request) async {
        try {
          final response = request.response;
          response.headers.set('Access-Control-Allow-Origin', '*');
          if (request.uri.path == '/data') {
            response.headers.contentType = ContentType.json;
            response.write(_snapshot());
          } else {
            response.headers.contentType = ContentType.html;
            response.write(trafficStatsHtml);
          }
          await response.close();
        } catch (error) {
          commonPrint.log('traffic stats http: $error', logLevel: LogLevel.warning);
        }
      });
    }).catchError((Object error) {
      commonPrint.log(
        'traffic stats http bind failed: $error',
        logLevel: LogLevel.warning,
      );
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    await _flush();
    await _server?.close(force: true);
  }
}

Future<void> startTrafficStats() => TrafficStats.start();

const String trafficStatsHtml = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>FlClash 流量统计</title>
<style>
  :root{--bg:#0f1216;--panel:#161b22;--panel2:#1c232c;--line:#252d38;--txt:#e6edf3;
        --dim:#8b949e;--up:#f0883e;--down:#3fb950;--accent:#58a6ff}
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  body{margin:0;background:var(--bg);color:var(--txt);
       font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif}
  .wrap{max-width:980px;margin:0 auto;padding:16px}
  header{display:flex;align-items:center;gap:12px;margin-bottom:14px;flex-wrap:wrap}
  h1{font-size:17px;margin:0;font-weight:600}
  .dot{width:8px;height:8px;border-radius:50%;background:#555}
  .dot.on{background:var(--down);box-shadow:0 0 8px var(--down)}
  .dot.off{background:#f85149}
  .grow{flex:1}
  button{background:var(--panel2);color:var(--txt);border:1px solid var(--line);
         border-radius:8px;padding:6px 12px;font-size:13px;cursor:pointer}
  button:hover{border-color:var(--accent)}
  .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-bottom:14px}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:12px 14px}
  .card .k{color:var(--dim);font-size:12px;margin-bottom:4px}
  .card .v{font-size:19px;font-weight:600;font-variant-numeric:tabular-nums}
  .card .v.up{color:var(--up)} .card .v.down{color:var(--down)}
  .tabs{display:flex;gap:8px;margin-bottom:10px;flex-wrap:wrap}
  .tab{padding:6px 14px;border-radius:999px;background:var(--panel2);border:1px solid var(--line);
       cursor:pointer;font-size:13px;color:var(--dim)}
  .tab.active{background:rgba(88,166,255,.15);border-color:var(--accent);color:var(--accent)}
  .panel{background:var(--panel);border:1px solid var(--line);border-radius:12px;overflow:hidden}
  table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}
  th,td{padding:9px 12px;text-align:right;font-size:13px;border-bottom:1px solid var(--line);white-space:nowrap}
  th{color:var(--dim);font-weight:500;font-size:12px;position:sticky;top:0;background:var(--panel);cursor:pointer}
  th:first-child,td:first-child{text-align:left;white-space:normal;word-break:break-all}
  tbody tr:hover{background:rgba(255,255,255,.03)}
  tbody tr:last-child td{border-bottom:none}
  .bar{position:relative}
  .bar i{position:absolute;left:0;bottom:0;height:2px;background:var(--accent);opacity:.55;border-radius:2px}
  .empty{padding:34px;text-align:center;color:var(--dim)}
  .foot{margin-top:14px;color:var(--dim);font-size:12px;line-height:1.8}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <span class="dot off" id="dot"></span>
    <h1>FlClash 流量统计</h1>
    <span class="grow"></span>
    <span id="status" style="color:var(--dim);font-size:12px"></span>
    <button onclick="exportCsv()">导出 CSV</button>
  </header>
  <div class="cards">
    <div class="card"><div class="k">今日上行</div><div class="v up" id="tUp">0 B</div></div>
    <div class="card"><div class="k">今日下行</div><div class="v down" id="tDown">0 B</div></div>
    <div class="card"><div class="k">今日合计</div><div class="v" id="tAll">0 B</div></div>
    <div class="card"><div class="k">活动连接</div><div class="v" id="tCon">0</div></div>
  </div>
  <div class="tabs" id="tabs"></div>
  <div class="panel">
    <table>
      <thead><tr>
        <th data-k="name">域名 / 分组</th><th data-k="up">上行</th>
        <th data-k="down">下行</th><th data-k="total">合计</th><th data-k="pct">占比</th>
      </tr></thead>
      <tbody id="tbody"></tbody>
    </table>
  </div>
  <div class="foot">
    <div>数据来自 FlClash 内核推送的连接流量，本地保存，不上传任何地方。</div>
    <div>采集地址 <span id="src"></span> · 保留 90 天</div>
  </div>
</div>
<script>
const $ = id => document.getElementById(id);
let snap = {today:'', live:0, days:{}};
let tab = 'today', sortKey = 'total', sortDesc = true;
const TABS = [['today','今日域名'],['yesterday','昨天'],['week','近7天'],
              ['days','按天'],['proc','今日进程'],['exit','今日出口']];

function fmt(n){
  n = Number(n)||0; const u=['B','KB','MB','GB','TB']; let i=0;
  while(n>=1024 && i<u.length-1){ n/=1024; i++; }
  return (i===0? Math.round(n) : n.toFixed(n<10?2:1))+' '+u[i];
}
function shift(n){
  const d = new Date(); d.setDate(d.getDate()+n);
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}
function bucket(day){ return (snap.days && snap.days[day]) || null; }
function rowsFor(){
  if(tab==='today'||tab==='yesterday'){
    const b = bucket(tab==='today'? snap.today : shift(-1));
    if(!b) return [];
    return Object.entries(b.domains||{}).map(([n,v])=>({name:n,up:v[0],down:v[1]}));
  }
  if(tab==='week'){
    const out={};
    for(let i=0;i<7;i++){
      const b = bucket(shift(-i)); if(!b) continue;
      for(const [n,v] of Object.entries(b.domains||{})){
        const o = out[n] || (out[n]={name:n,up:0,down:0});
        o.up+=v[0]; o.down+=v[1];
      }
    }
    return Object.values(out);
  }
  if(tab==='proc'||tab==='exit'){
    const b = bucket(snap.today); if(!b) return [];
    const src = tab==='proc' ? (b.procs||{}) : (b.exits||{});
    return Object.entries(src).map(([n,v])=>({name:n,up:v[0],down:v[1]}));
  }
  if(tab==='days'){
    return Object.keys(snap.days||{}).sort().reverse().map(k=>{
      let up=0,dn=0;
      for(const v of Object.values(snap.days[k].domains||{})){ up+=v[0]; dn+=v[1]; }
      return {name:k,up,down:dn};
    });
  }
  return [];
}
function render(){
  const rows = rowsFor();
  rows.forEach(r=>r.total=r.up+r.down);
  const sum = rows.reduce((a,r)=>a+r.total,0);
  rows.sort((a,b)=>{
    const x=a[sortKey], y=b[sortKey];
    if(typeof x==='string') return sortDesc ? y.localeCompare(x) : x.localeCompare(y);
    return sortDesc ? y-x : x-y;
  });
  $('tbody').innerHTML = rows.length
    ? rows.slice(0,300).map(r=>{
        const pct = sum? (r.total*100/sum):0;
        return `<tr><td class="bar">${esc(r.name)}<i style="width:${pct.toFixed(1)}%"></i></td>
          <td style="color:var(--up)">${fmt(r.up)}</td>
          <td style="color:var(--down)">${fmt(r.down)}</td>
          <td>${fmt(r.total)}</td>
          <td style="color:var(--dim)">${pct.toFixed(1)}%</td></tr>`;
      }).join('')
    : '<tr><td colspan="5" class="empty">还没有数据，先用一会儿再刷新。</td></tr>';
  const b = bucket(snap.today);
  let u=0,dn=0;
  if(b) for(const v of Object.values(b.domains||{})){ u+=v[0]; dn+=v[1]; }
  $('tUp').textContent = fmt(u);
  $('tDown').textContent = fmt(dn);
  $('tAll').textContent = fmt(u+dn);
  $('tCon').textContent = snap.live|0;
  buildTabs();
}
function esc(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function buildTabs(){
  $('tabs').innerHTML = TABS.map(([k,t])=>
    `<div class="tab${k===tab?' active':''}" data-t="${k}">${t}</div>`).join('');
  for(const el of $('tabs').children) el.onclick=()=>{tab=el.dataset.t;render();};
}
document.querySelectorAll('th').forEach(th=>{
  th.onclick=()=>{const k=th.dataset.k; if(k==='pct')return;
    if(sortKey===k) sortDesc=!sortDesc; else {sortKey=k; sortDesc=(k!=='name');}
    render();};
});
function exportCsv(){
  const rows = rowsFor(); rows.forEach(r=>r.total=r.up+r.down);
  const csv = ['名称,上行字节,下行字节,合计字节']
    .concat(rows.map(r=>[r.name,r.up,r.down,r.total].join(','))).join('\n');
  const a=document.createElement('a');
  a.href=URL.createObjectURL(new Blob(['\ufeff'+csv],{type:'text/csv'}));
  a.download='flclash-traffic-'+tab+'-'+snap.today+'.csv'; a.click();
}
async function poll(){
  try{
    const r = await fetch('/data',{cache:'no-store'});
    snap = await r.json();
    $('dot').className='dot on';
    $('status').textContent = new Date().toLocaleTimeString();
    render();
  }catch(e){
    $('dot').className='dot off';
    $('status').textContent='未连接';
  }
}
$('src').textContent = location.origin;
poll(); setInterval(poll, 3000);
</script>
</body>
</html>
''';
