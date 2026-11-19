#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把自定义功能注入到上游 FlClash 源码里。

设计原则：只新增文件 + 对极少数稳定锚点做精确替换，仓库里保存的仍是上游原始代码，
所以同步上游时不会产生冲突，上游改了基线也只需要调这里的一个锚点。

自定义模块：
  lib/custom/traffic_stats.dart        每日/按域名流量统计（监听内核推送的连接流量）
  lib/custom/traffic_stats_view.dart   流量统计页面
  lib/custom/core_hooks.dart           内核 Hook：每次下发配置前跑 JS 脚本
  lib/custom/core_hooks_view.dart      内核 Hook 的 GUI（列表 / 编辑 / 启停）

注入点：
  lib/main.dart                      启动流量统计服务
  lib/providers/action.dart          引入 core_hooks
  lib/providers/actions/setup.dart   配置下发前执行 hooks（setup.dart 是 part 文件）
  lib/views/tools.dart               设置里加「内核 Hook」「流量统计」两个入口
"""

import pathlib
import sys

for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAIN = ROOT / "lib" / "main.dart"
ACTION = ROOT / "lib" / "providers" / "action.dart"
SETUP = ROOT / "lib" / "providers" / "actions" / "setup.dart"
TOOLS = ROOT / "lib" / "views" / "tools.dart"

CUSTOM_FILES = [
    "lib/custom/traffic_stats.dart",
    "lib/custom/traffic_stats_view.dart",
    "lib/custom/core_hooks.dart",
    "lib/custom/core_hooks_view.dart",
]

# ---------- main.dart：启动统计服务 ----------
IMPORT_LINE = "import 'custom/traffic_stats.dart';"
IMPORT_ANCHOR = "import 'common/window.dart';"
CALL_LINE = "        unawaited(startTrafficStats());"
CALL_ANCHOR = "        final container = await bootstrap.init(version);"

# ---------- action.dart：import core_hooks ----------
ACTION_IMPORT_LINE = "import 'package:fl_clash/custom/core_hooks.dart';"
ACTION_IMPORT_ANCHOR = "import 'package:fl_clash/common/system_dns.dart';"

# ---------- setup.dart：配置下发前跑 hooks ----------
SETUP_ANCHOR = "      rawConfig = await handleEvaluate(scriptContent!, rawConfig);"
SETUP_LINE = "    rawConfig = await applyCoreHooks(rawConfig);"

# ---------- tools.dart：菜单入口 ----------
TOOLS_IMPORT_LINES = (
    "import 'package:fl_clash/custom/core_hooks_view.dart';",
    "import 'package:fl_clash/custom/traffic_stats_view.dart';",
)
TOOLS_IMPORT_ANCHOR = "import 'theme.dart';"
TOOLS_ITEM_LINES = (
    "        const _CoreHooksItem(),",
    "        const _TrafficStatsItem(),",
)
TOOLS_ITEM_ANCHOR = "        const _GeneralItem(),"

TOOLS_CLASSES = """

class _CoreHooksItem extends StatelessWidget {
  const _CoreHooksItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.wrench),
      title: const Text('内核 Hook'),
      widget: const CoreHooksView(),
    );
  }
}

class _TrafficStatsItem extends StatelessWidget {
  const _TrafficStatsItem();

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.dashboard),
      title: const Text('流量统计'),
      widget: const TrafficStatsView(),
    );
  }
}
"""


def fail(message):
    print("ERROR: " + message, file=sys.stderr)
    sys.exit(1)


def ensure_custom_files():
    missing = [f for f in CUSTOM_FILES if not (ROOT / f).exists()]
    if missing:
        fail("缺少自定义文件：" + ", ".join(missing))
    print("自定义文件就位：%d 个" % len(CUSTOM_FILES))


def patch_main():
    if not MAIN.exists():
        fail("找不到 lib/main.dart")
    text = MAIN.read_text(encoding="utf-8")
    changed = False
    if IMPORT_LINE not in text:
        if IMPORT_ANCHOR not in text:
            fail("main.dart 找不到 import 锚点：" + IMPORT_ANCHOR)
        text = text.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + "\n" + IMPORT_LINE, 1)
        changed = True
    if CALL_LINE.strip() not in text:
        if CALL_ANCHOR not in text:
            fail("main.dart 找不到初始化锚点：" + CALL_ANCHOR)
        text = text.replace(CALL_ANCHOR, CALL_ANCHOR + "\n" + CALL_LINE, 1)
        changed = True
    if changed:
        MAIN.write_text(text, encoding="utf-8")
        print("已注入 lib/main.dart")
    else:
        print("lib/main.dart 已是最新")


def patch_action():
    if not ACTION.exists():
        fail("找不到 lib/providers/action.dart")
    text = ACTION.read_text(encoding="utf-8")
    if ACTION_IMPORT_LINE in text:
        print("lib/providers/action.dart 已是最新")
        return
    if ACTION_IMPORT_ANCHOR not in text:
        fail("action.dart 找不到 import 锚点：" + ACTION_IMPORT_ANCHOR)
    text = text.replace(
        ACTION_IMPORT_ANCHOR, ACTION_IMPORT_ANCHOR + "\n" + ACTION_IMPORT_LINE, 1
    )
    ACTION.write_text(text, encoding="utf-8")
    print("已注入 lib/providers/action.dart")


def patch_setup():
    if not SETUP.exists():
        fail("找不到 lib/providers/actions/setup.dart")
    text = SETUP.read_text(encoding="utf-8")
    if SETUP_LINE.strip() in text:
        print("lib/providers/actions/setup.dart 已是最新")
        return
    if SETUP_ANCHOR not in text:
        fail("setup.dart 找不到锚点：" + SETUP_ANCHOR)
    text = text.replace(SETUP_ANCHOR, SETUP_ANCHOR + "\n" + SETUP_LINE, 1)
    SETUP.write_text(text, encoding="utf-8")
    print("已注入 lib/providers/actions/setup.dart（内核 Hook 生效点）")


def patch_tools():
    if not TOOLS.exists():
        fail("找不到 lib/views/tools.dart")
    text = TOOLS.read_text(encoding="utf-8")
    changed = False

    for line in TOOLS_IMPORT_LINES:
        if line not in text:
            if TOOLS_IMPORT_ANCHOR not in text:
                fail("tools.dart 找不到 import 锚点：" + TOOLS_IMPORT_ANCHOR)
            text = text.replace(TOOLS_IMPORT_ANCHOR, TOOLS_IMPORT_ANCHOR + "\n" + line, 1)
            changed = True

    for line in TOOLS_ITEM_LINES:
        if line.strip() not in text:
            if TOOLS_ITEM_ANCHOR not in text:
                fail("tools.dart 找不到菜单锚点：" + TOOLS_ITEM_ANCHOR)
            text = text.replace(TOOLS_ITEM_ANCHOR, line + "\n" + TOOLS_ITEM_ANCHOR, 1)
            changed = True

    if "_CoreHooksItem extends StatelessWidget" not in text:
        text = text.rstrip() + "\n" + TOOLS_CLASSES
        changed = True

    if changed:
        TOOLS.write_text(text, encoding="utf-8")
        print("已注入 lib/views/tools.dart（内核 Hook + 流量统计 入口）")
    else:
        print("lib/views/tools.dart 已是最新")


def main():
    print("工作目录：%s" % ROOT)
    ensure_custom_files()
    patch_main()
    patch_action()
    patch_setup()
    patch_tools()
    print("完成：内核 Hook（工具 → 内核 Hook）+ 流量统计 + 网页版 18999")


if __name__ == "__main__":
    main()
