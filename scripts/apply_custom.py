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

IMPORT_LINE = "import 'custom/traffic_stats.dart';"
IMPORT_ANCHOR = "import 'common/window.dart';"

CALL_LINE = "        unawaited(startTrafficStats());"
CALL_ANCHOR = "        final container = await bootstrap.init(version);"

CUSTOM_FILES = [
    "lib/custom/traffic_stats.dart",
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
        text = text.replace(
            IMPORT_ANCHOR, IMPORT_ANCHOR + "\n" + IMPORT_LINE, 1
        )
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


def main():
    print("工作目录：%s" % ROOT)
    ensure_custom_files()
    patch_main()
    print("完成：自定义流量统计已就位（http://127.0.0.1:18999）")


if __name__ == "__main__":
    main()
