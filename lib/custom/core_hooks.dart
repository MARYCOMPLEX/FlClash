// 自定义功能：内核启动 Hook（Core Hooks）
//
// 每次 FlClash 构建并下发内核配置时（= 每次启动/重启内核、切换订阅、改配置），
// 会依次执行这里启用的 JS 脚本，脚本拿到即将下发的配置对象，可以任意修改后返回。
//
// 脚本运行在 FlClash 自带的 QuickJS 引擎里（和「配置脚本」同一套），不依赖外部解释器：
//
//   // 例：让这条规则每次都出现在规则最前面（订阅更新也不会丢）
//   if (!config.rules) config.rules = [];
//   const r = "DOMAIN,play.googleapis.com,REJECT";
//   if (!config.rules.includes(r)) config.rules.unshift(r);
//   return config;
//
// 存储：homeDir/core_hooks.json

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/javascript.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class CoreHook {
  CoreHook({
    required this.id,
    required this.label,
    required this.script,
    this.enabled = true,
    this.order = 0,
    this.lastRun,
    this.lastStatus = '',
    this.lastMessage = '',
  });

  String id;
  String label;
  String script;
  bool enabled;
  int order;
  DateTime? lastRun;
  String lastStatus;
  String lastMessage;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'script': script,
    'enabled': enabled,
    'order': order,
    'lastRun': lastRun?.toIso8601String(),
    'lastStatus': lastStatus,
    'lastMessage': lastMessage,
  };

  factory CoreHook.fromJson(Map<String, Object?> json) {
    DateTime? lastRun;
    final rawLastRun = json['lastRun'];
    if (rawLastRun is String && rawLastRun.isNotEmpty) {
      lastRun = DateTime.tryParse(rawLastRun);
    }
    return CoreHook(
      id: '${json['id'] ?? ''}',
      label: '${json['label'] ?? '未命名'}',
      script: '${json['script'] ?? ''}',
      enabled: json['enabled'] != false,
      order: (json['order'] as num?)?.toInt() ?? 0,
      lastRun: lastRun,
      lastStatus: '${json['lastStatus'] ?? ''}',
      lastMessage: '${json['lastMessage'] ?? ''}',
    );
  }

  CoreHook copy() => CoreHook.fromJson(toJson());
}

class CoreHooks {
  CoreHooks._();

  static final CoreHooks instance = CoreHooks._();

  final List<CoreHook> hooks = <CoreHook>[];

  /// GUI 监听这个，值变化时刷新
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  File? _file;
  bool _loaded = false;

  static const String defaultScript = '''// config 是即将下发的内核配置对象，改完 return 回去
// 这条默认 hook：把 Google 遥测上报端点直接拒绝，避免 Antigravity 的
// language_server 疯狂重试上传（日志里 10 万次 POST play.googleapis.com/log）
if (!config.rules) config.rules = [];
const rule = "DOMAIN,play.googleapis.com,REJECT";
if (config.rules.indexOf(rule) < 0) {
  config.rules.unshift(rule);
}
return config;
''';

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final home = await appPath.homeDirPath;
      _file = File(p.join(home, 'core_hooks.json'));
      if (await _file!.exists()) {
        final raw = jsonDecode(await _file!.readAsString());
        if (raw is Map && raw['hooks'] is List) {
          hooks
            ..clear()
            ..addAll(
              (raw['hooks'] as List).whereType<Map>().map(
                (e) => CoreHook.fromJson(Map<String, Object?>.from(e)),
              ),
            );
        }
      }
      if (hooks.isEmpty) {
        hooks.add(
          CoreHook(
            id: 'builtin-block-telemetry',
            label: '拦截 Google 遥测上报',
            script: defaultScript,
            enabled: true,
            order: 0,
          ),
        );
        await save();
      }
    } catch (error) {
      commonPrint.log(
        'core hooks load failed: $error',
        logLevel: LogLevel.warning,
      );
    }
    revision.value++;
  }

  Future<void> save() async {
    final file = _file;
    if (file == null) {
      return;
    }
    try {
      final payload = <String, Object>{
        'version': 1,
        'hooks': hooks.map((e) => e.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (error) {
      commonPrint.log(
        'core hooks save failed: $error',
        logLevel: LogLevel.warning,
      );
    }
  }

  List<CoreHook> get enabledHooks {
    final list = hooks.where((e) => e.enabled).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// 依次执行所有启用的 hook，任何单个 hook 出错只记录，不阻断内核启动
  Future<Map<String, dynamic>> apply(Map<String, dynamic> config) async {
    await load();
    final list = enabledHooks;
    if (list.isEmpty) {
      return config;
    }
    var current = config;
    for (final hook in list) {
      final watch = Stopwatch()..start();
      try {
        final next = await handleEvaluate(hook.script, current);
        current = next;
        hook.lastStatus = 'ok';
        hook.lastMessage = '${watch.elapsedMilliseconds} ms';
      } catch (error) {
        hook.lastStatus = 'error';
        hook.lastMessage = error.toString();
        commonPrint.log(
          'core hook "${hook.label}" failed: $error',
          logLevel: LogLevel.warning,
        );
      }
      hook.lastRun = DateTime.now();
    }
    revision.value++;
    unawaited(save());
    return current;
  }

  /// GUI 里「试跑」用：对给定配置跑一次，返回每条 hook 的结果
  Future<List<String>> dryRun(Map<String, dynamic> config) async {
    await load();
    final lines = <String>[];
    var current = config;
    for (final hook in enabledHooks) {
      final watch = Stopwatch()..start();
      try {
        current = await handleEvaluate(hook.script, current);
        lines.add('${hook.label}: OK (${watch.elapsedMilliseconds} ms)');
      } catch (error) {
        lines.add('${hook.label}: 失败 - $error');
      }
    }
    if (lines.isEmpty) {
      lines.add('没有启用的 hook');
    }
    return lines;
  }

  CoreHook createHook({String? label}) {
    final hook = CoreHook(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label ?? '新 Hook',
      script: defaultScript,
      order: hooks.length,
    );
    hooks.add(hook);
    revision.value++;
    unawaited(save());
    return hook;
  }

  void removeHook(String id) {
    hooks.removeWhere((e) => e.id == id);
    revision.value++;
    unawaited(save());
  }

  void moveHook(String id, int delta) {
    final index = hooks.indexWhere((e) => e.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= hooks.length) {
      return;
    }
    final hook = hooks.removeAt(index);
    hooks.insert(target, hook);
    for (var i = 0; i < hooks.length; i++) {
      hooks[i].order = i;
    }
    revision.value++;
    unawaited(save());
  }
}

final coreHooks = CoreHooks.instance;

/// 注入到 setup 流程里的入口
Future<Map<String, dynamic>> applyCoreHooks(Map<String, dynamic> config) {
  return coreHooks.apply(config);
}
