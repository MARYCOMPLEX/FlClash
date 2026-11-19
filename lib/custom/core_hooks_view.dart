// 自定义功能：内核 Hook 的 GUI（工具 → 内核 Hook）
//
// Hook 就是一段 JS：内核每次启动/重启、切换订阅、改配置时，
// FlClash 会用它自己的 QuickJS 引擎依次执行，脚本拿到即将下发的配置对象。

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

import 'core_hooks.dart';

const _accent = Color(0xFF58A6FF);
const _upColor = Color(0xFFF0883E);
const _okColor = Color(0xFF3FB950);
const _errColor = Color(0xFFF85149);

class CoreHooksView extends StatefulWidget {
  const CoreHooksView({super.key});

  @override
  State<CoreHooksView> createState() => _CoreHooksViewState();
}

class _CoreHooksViewState extends State<CoreHooksView> {
  @override
  void initState() {
    super.initState();
    coreHooks.load().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
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

    return Scaffold(
      title: '内核 Hook',
      body: ValueListenableBuilder<int>(
        valueListenable: coreHooks.revision,
        builder: (_, __, ___) {
          final hooks = coreHooks.hooks;
          final enabledCount = coreHooks.enabledHooks.length;
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: context.sectionsTopPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '每次启动 / 重启内核、切换订阅、改配置时执行',
                        style: TextStyle(fontSize: 12, color: textColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已启用 $enabledCount / 共 ${hooks.length} 个 · '
                        '脚本用 FlClash 自带的 JS 引擎，入参 config 是即将下发的配置对象',
                        style: TextStyle(fontSize: 11, color: subColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: hooks.isEmpty
                      ? Center(
                          child: Text(
                            '还没有 Hook，点下面新建一个',
                            style: TextStyle(color: subColor, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: hooks.length,
                          itemBuilder: (_, index) {
                            final hook = hooks[index];
                            final statusColor = hook.lastStatus == 'ok'
                                ? _okColor
                                : (hook.lastStatus == 'error'
                                      ? _errColor
                                      : subColor);
                            final statusText = hook.lastStatus == 'ok'
                                ? '上次 OK ${hook.lastMessage}'
                                : (hook.lastStatus == 'error'
                                      ? '上次失败：${hook.lastMessage}'
                                      : '还没执行过');
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: hook.enabled
                                      ? _accent.withValues(alpha: 0.35)
                                      : const Color(0x00000000),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          hook.enabled = !hook.enabled;
                                          coreHooks.revision.value++;
                                          coreHooks.save();
                                        },
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: hook.enabled
                                                ? _accent
                                                : const Color(0x00000000),
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                            border: Border.all(
                                              color: hook.enabled
                                                  ? _accent
                                                  : subColor,
                                            ),
                                          ),
                                          child: hook.enabled
                                              ? const Text(
                                                  '✓',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF06101C),
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          hook.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                      _MiniButton(
                                        text: '上移',
                                        color: subColor,
                                        onTap: () =>
                                            coreHooks.moveHook(hook.id, -1),
                                      ),
                                      const SizedBox(width: 6),
                                      _MiniButton(
                                        text: '下移',
                                        color: subColor,
                                        onTap: () =>
                                            coreHooks.moveHook(hook.id, 1),
                                      ),
                                      const SizedBox(width: 6),
                                      _MiniButton(
                                        text: '编辑',
                                        color: _accent,
                                        onTap: () => Navigator.of(context).push(
                                          PageRouteBuilder(
                                            pageBuilder: (_, __, ___) =>
                                                _HookEditor(hook: hook),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _MiniButton(
                                        text: '删除',
                                        color: _upColor,
                                        onTap: () =>
                                            coreHooks.removeHook(hook.id),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    statusText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GestureDetector(
                    onTap: () {
                      final hook = coreHooks.createHook();
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => _HookEditor(hook: hook),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _accent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text(
                        '+ 新建 Hook',
                        style: TextStyle(
                          fontSize: 13,
                          color: _accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.text,
    required this.color,
    required this.onTap,
  });

  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color)),
      ),
    );
  }
}

class _HookEditor extends StatefulWidget {
  const _HookEditor({required this.hook});

  final CoreHook hook;

  @override
  State<_HookEditor> createState() => _HookEditorState();
}

class _HookEditorState extends State<_HookEditor> {
  late final TextEditingController _labelController;
  late final TextEditingController _scriptController;
  final FocusNode _labelFocus = FocusNode();
  final FocusNode _scriptFocus = FocusNode();
  String _message = '';

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.hook.label);
    _scriptController = TextEditingController(text: widget.hook.script);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _scriptController.dispose();
    _labelFocus.dispose();
    _scriptFocus.dispose();
    super.dispose();
  }

  void _save() {
    widget.hook.label = _labelController.text.trim().isEmpty
        ? '未命名'
        : _labelController.text.trim();
    widget.hook.script = _scriptController.text;
    coreHooks.revision.value++;
    coreHooks.save();
    setState(() => _message = '已保存，重启内核后生效');
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
    final editorStyle = TextStyle(
      fontSize: 12.5,
      height: 1.5,
      fontFamily: 'Consolas',
      color: textColor,
    );

    return Scaffold(
      title: '编辑 Hook',
      body: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: EditableText(
                controller: _labelController,
                focusNode: _labelFocus,
                style: TextStyle(fontSize: 13, color: textColor),
                cursorColor: _accent,
                backgroundCursorColor: subColor,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: EditableText(
                    controller: _scriptController,
                    focusNode: _scriptFocus,
                    maxLines: null,
                    style: editorStyle,
                    cursorColor: _accent,
                    backgroundCursorColor: subColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '保存',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF06101C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _message,
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
