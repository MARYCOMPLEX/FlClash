#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把自定义功能注入到上游 FlClash 源码里。

设计原则：只新增文件 + 对极少数稳定锚点做精确替换，仓库里保存的仍是上游原始代码，
所以同步上游时不会产生冲突，上游改了基线也只需要调这里的一个锚点。
"""

import pathlib
import sys

# Windows runner 的 stdout 默认是 cp1252，直接 print 中文会炸
for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAIN = ROOT / "lib" / "main.dart"
TOOLS = ROOT / "lib" / "views" / "tools.dart"

# ---------- main.dart：启动统计服务 ----------
IMPORT_LINE = "import 'custom/traffic_stats.dart';"
IMPORT_ANCHOR = "import 'common/window.dart';"

CALL_LINE = "        unawaited(startTrafficStats());"
CALL_ANCHOR = "        final container = await bootstrap.init(version);"

# ---------- views/tools.dart：设置里加「流量统计」入口 ----------
TOOLS_IMPORT_LINE = "import 'package:fl_clash/custom/traffic_stats_view.dart';"
TOOLS_IMPORT_ANCHOR = "import 'theme.dart';"

TOOLS_ITEM_LINE = "        const _TrafficStatsItem(),"
TOOLS_ITEM_ANCHOR = "        const _GeneralItem(),"

TOOLS_CLASS = """

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

CUSTOM_FILES = [
    "lib/custom/traffic_stats.dart",
    "lib/custom/traffic_stats_view.dart",
]


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
            fail("main.dart 里找不到 import 锚点：" + IMPORT_ANCHOR)
        text = text.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + "\n" + IMPORT_LINE, 1)
        changed = True

    if CALL_LINE.strip() not in text:
        if CALL_ANCHOR not in text:
            fail("main.dart 里找不到初始化锚点：" + CALL_ANCHOR)
        text = text.replace(CALL_ANCHOR, CALL_ANCHOR + "\n" + CALL_LINE, 1)
        changed = True

    if changed:
        MAIN.write_text(text, encoding="utf-8")
        print("已注入 lib/main.dart")
    else:
        print("lib/main.dart 已是最新，跳过")


def patch_tools():
    if not TOOLS.exists():
        fail("找不到 lib/views/tools.dart")
    text = TOOLS.read_text(encoding="utf-8")
    changed = False

    if TOOLS_IMPORT_LINE not in text:
        if TOOLS_IMPORT_ANCHOR not in text:
            fail("tools.dart 里找不到 import 锚点：" + TOOLS_IMPORT_ANCHOR)
        text = text.replace(
            TOOLS_IMPORT_ANCHOR,
            TOOLS_IMPORT_ANCHOR + "\n" + TOOLS_IMPORT_LINE,
            1,
        )
        changed = True

    if TOOLS_ITEM_LINE.strip() not in text:
        if TOOLS_ITEM_ANCHOR not in text:
            fail("tools.dart 里找不到菜单锚点：" + TOOLS_ITEM_ANCHOR)
        text = text.replace(
            TOOLS_ITEM_ANCHOR,
            TOOLS_ITEM_LINE + "\n" + TOOLS_ITEM_ANCHOR,
            1,
        )
        changed = True

    if "_TrafficStatsItem extends StatelessWidget" not in text:
        text = text.rstrip() + "\n" + TOOLS_CLASS
        changed = True

    if changed:
        TOOLS.write_text(text, encoding="utf-8")
        print("已注入 lib/views/tools.dart（设置 → 流量统计）")
    else:
        print("lib/views/tools.dart 已是最新，跳过")


def main():
    print("工作目录：%s" % ROOT)
    ensure_custom_files()
    patch_main()
    patch_tools()
    print("完成：客户端内「流量统计」页 + 网页版 http://127.0.0.1:18999")


if __name__ == "__main__":
    main()
