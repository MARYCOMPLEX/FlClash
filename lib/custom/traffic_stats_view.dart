// 自定义功能：FlClash 客户端内的「流量统计」页面
// 入口：设置 → 工具 → 流量统计

import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

import 'traffic_stats.dart';

const _tabNames = <String>['今日域名', '近7天', '今日进程', '今日出口'];

class TrafficStatsView extends StatefulWidget {
  const TrafficStatsView({super.key});

  @override
  State<TrafficStatsView> createState() => _TrafficStatsViewState();
}

class _TrafficStatsViewState extends State<TrafficStatsView> {
  int _tab = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _fmt(num? value) {
    var n = (value ?? 0).toDouble();
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    if (i == 0) {
      return '${n.round()} ${units[i]}';
    }
    return '${n.toStringAsFixed(n < 10 ? 2 : 1)} ${units[i]}';
  }

  List<MapEntry<String, List<int>>> _rows() {
    final stats = TrafficStats.instance;
    final today = stats.dataMap()['today'] as String;
    switch (_tab) {
      case 1:
        final acc = <String, List<int>>{};
        for (final day in stats.allDays.take(7)) {
          final detail = stats.dayDetail(day)['domains'] ?? {};
          detail.forEach((name, value) {
            final cur = acc[name] ?? <int>[0, 0];
            acc[name] = <int>[cur[0] + value[0], cur[1] + value[1]];
          });
        }
        return acc.entries.toList();
      case 2:
        return (stats.dayDetail(today)['procs'] ?? {}).entries.toList();
      case 3:
        return (stats.dayDetail(today)['exits'] ?? {}).entries.toList();
      default:
        return (stats.dayDetail(today)['domains'] ?? {}).entries.toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF1C232C)
        : const Color(0xFFFFFFFF);
    final textColor = isDark
        ? const Color(0xFFE6EDF3)
        : const Color(0xFF1F2328);
    final subColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF6E7781);
    const upColor = Color(0xFFF0883E);
    const downColor = Color(0xFF3FB950);
    const accent = Color(0xFF58A6FF);

    final stats = TrafficStats.instance;
    final today = stats.dataMap()['today'] as String;
    final todayDomains = stats.dayDetail(today)['domains'] ?? {};
    var up = 0;
    var down = 0;
    for (final value in todayDomains.values) {
      up += value[0];
      down += value[1];
    }

    final rows = _rows()
      ..sort((a, b) {
        final at = a.value[0] + a.value[1];
        final bt = b.value[0] + b.value[1];
        return bt.compareTo(at);
      });
    final total = rows.fold<int>(0, (s, e) => s + e.value[0] + e.value[1]);

    Widget card(String label, String value, Color color) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: subColor)),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      title: '流量统计',
      body: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                card('今日上行', _fmt(up), upColor),
                card('今日下行', _fmt(down), downColor),
                card('今日合计', _fmt(up + down), textColor),
                card('活动连接', '${stats.dataMap()['live']}', accent),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < _tabNames.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _tab == i
                              ? accent.withValues(alpha: 0.15)
                              : cardColor,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _tab == i ? accent : const Color(0x00000000),
                          ),
                        ),
                        child: Text(
                          _tabNames[i],
                          style: TextStyle(
                            fontSize: 12,
                            color: _tab == i ? accent : subColor,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      _tab == 2 ? '进程' : (_tab == 3 ? '出口节点' : '域名'),
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '上行',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '下行',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ),
                  Expanded(
                    flex: 13,
                    child: Text(
                      '占比',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        '还没有数据，用一会儿再回来刷新',
                        style: TextStyle(color: subColor, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: rows.length,
                      itemBuilder: (_, index) {
                        final entry = rows[index];
                        final itemTotal = entry.value[0] + entry.value[1];
                        final pct = total == 0 ? 0.0 : itemTotal * 100 / total;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 1),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: index.isEven
                                ? cardColor.withValues(alpha: 0.45)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  entry.key,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _fmt(entry.value[0]),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: upColor,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _fmt(entry.value[1]),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: downColor,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 13,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    height: 3,
                                    width: 70,
                                    decoration: BoxDecoration(
                                      color: subColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: (pct / 100).clamp(0.0, 1.0),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: accent,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 42,
                                child: Text(
                                  '${pct.toStringAsFixed(1)}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: subColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
