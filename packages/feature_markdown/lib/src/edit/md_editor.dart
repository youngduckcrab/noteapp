// The source editor (08-markdown 8.7, B-8): a monospace multi-line TextField that scrolls
// itself (the cursor stays above the keyboard), autocorrect and suggestions off, undo /
// redo through the controller's capped history (Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y are routed
// to it, not to the field's own unbounded one — edit/bounded_undo.dart), the
// reading width of the view, Tab / Shift+Tab = indent / outdent the current lines, and a
// symbol row above the keyboard (# - [ ] * ` $ | > indent outdent).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../markdown_keys.dart';
import '../render/md_style.dart';
import '../strings_ko.dart';

/// Two spaces per indent step.
const String kIndentUnit = '  ';

class MdEditor extends StatelessWidget {
  const MdEditor({
    super.key,
    required this.controller,
    required this.onUndo,
    required this.onRedo,
    required this.focusNode,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final FocusNode focusNode;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final t = StyleTokens.of(context);
    final base = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    final style = base.copyWith(
      fontFamily: kMonoFamily,
      fontFamilyFallback: kMonoFallback,
      fontSize: 15,
      height: 1.5,
      color: t.textPrimary,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = MdStyle.sidePadding(constraints.maxWidth);
        final side = ((constraints.maxWidth - kReadingWidth) / 2).clamp(
          pad,
          double.infinity,
        );
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.tab): _IndentIntent(true),
            SingleActivator(LogicalKeyboardKey.tab, shift: true): _IndentIntent(
              false,
            ),
          },
          child: Actions(
            actions: {
              _IndentIntent: CallbackAction<_IndentIntent>(
                onInvoke: (i) {
                  if (!readOnly) indentLines(controller, indent: i.indent);
                  return null;
                },
              ),
              // Overrides the field's own undo (UndoHistory's actions are overridable).
              UndoTextIntent: CallbackAction<UndoTextIntent>(
                onInvoke: (_) {
                  if (!readOnly) onUndo();
                  return null;
                },
              ),
              RedoTextIntent: CallbackAction<RedoTextIntent>(
                onInvoke: (_) {
                  if (!readOnly) onRedo();
                  return null;
                },
              ),
            },
            child: TextField(
              key: MarkdownKeys.editor,
              controller: controller,
              focusNode: focusNode,
              readOnly: readOnly,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              textCapitalization: TextCapitalization.none,
              textAlignVertical: TextAlignVertical.top,
              style: style,
              cursorColor: t.accent,
              scrollPadding: const EdgeInsets.all(48),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: MdStrings.editorHint,
                hintStyle: style.copyWith(color: t.textTertiary),
                contentPadding: EdgeInsets.fromLTRB(side, 20, side, 16),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IndentIntent extends Intent {
  const _IndentIntent(this.indent);
  final bool indent;
}

/// Indents (or outdents) every line the selection touches by [kIndentUnit].
void indentLines(TextEditingController c, {required bool indent}) {
  final v = c.value;
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : const TextSelection.collapsed(offset: 0);
  final from =
      text.lastIndexOf('\n', (sel.start - 1).clamp(-1, text.length)) + 1;
  var to = text.indexOf('\n', sel.end.clamp(0, text.length));
  if (to < 0) to = text.length;
  final lines = text.substring(from, to).split('\n');
  var delta = 0;
  var firstDelta = 0;
  final changed = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    String next;
    if (indent) {
      next = '$kIndentUnit$l';
    } else if (l.startsWith(kIndentUnit)) {
      next = l.substring(kIndentUnit.length);
    } else if (l.startsWith(' ') || l.startsWith('\t')) {
      next = l.substring(1);
    } else {
      next = l;
    }
    final d = next.length - l.length;
    if (i == 0) firstDelta = d;
    delta += d;
    changed.add(next);
  }
  final out = text.replaceRange(from, to, changed.join('\n'));
  int move(int o, {required bool start}) =>
      (o + (start ? firstDelta : delta)).clamp(from, out.length);
  c.value = TextEditingValue(
    text: out,
    selection: sel.isCollapsed
        ? TextSelection.collapsed(offset: move(sel.start, start: true))
        : TextSelection(
            baseOffset: move(
              sel.baseOffset,
              start: sel.baseOffset <= sel.extentOffset,
            ),
            extentOffset: move(
              sel.extentOffset,
              start: sel.extentOffset < sel.baseOffset,
            ),
          ),
  );
}

/// Inserts [snippet] at the selection (replacing it); for line starters ('# ', '- ',
/// '> ', '- [ ] ') at the start of the current line instead.
void insertSnippet(
  TextEditingController c,
  String snippet, {
  bool lineStart = false,
}) {
  final v = c.value;
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  if (lineStart) {
    final at =
        text.lastIndexOf('\n', (sel.start - 1).clamp(-1, text.length)) + 1;
    final out = text.replaceRange(at, at, snippet);
    c.value = TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: sel.end + snippet.length),
    );
    return;
  }
  final out = text.replaceRange(sel.start, sel.end, snippet);
  c.value = TextEditingValue(
    text: out,
    selection: TextSelection.collapsed(offset: sel.start + snippet.length),
  );
}

/// The symbol row above the keyboard while editing.
class MdAccessoryRow extends StatelessWidget {
  const MdAccessoryRow({
    super.key,
    required this.controller,
    required this.focusNode,
    this.undo,
    this.onUndo,
    this.onRedo,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Shown when the top bar is narrow ([↶][↷] move here).
  final ValueListenable<UndoHistoryValue>? undo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final t = StyleTokens.of(context);
    final textStyle = TextStyle(
      fontFamily: kMonoFamily,
      fontFamilyFallback: kMonoFallback,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: t.textPrimary,
    );
    Widget symbol(
      String name,
      String label,
      String snippet, {
      bool line = false,
    }) => _AccessoryButton(
      key: MarkdownKeys.accessoryButton(name),
      tooltip: label,
      onPressed: () {
        insertSnippet(controller, snippet, lineStart: line);
        focusNode.requestFocus();
      },
      child: Text(label, style: textStyle),
    );
    Widget icon(
      String name,
      AppIconKind kind,
      String tooltip,
      VoidCallback? on,
    ) => _AccessoryButton(
      key: MarkdownKeys.accessoryButton(name),
      tooltip: tooltip,
      onPressed: on,
      child: AppIcon(
        kind,
        size: 20,
        color: on == null ? t.textTertiary : t.textPrimary,
      ),
    );
    final undo = this.undo;
    return Material(
      key: MarkdownKeys.accessory,
      color: t.toolbar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 48,
            child: _EdgeFade(
              color: t.toolbar,
              builder: (scroll) => ListView(
                controller: scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                children: [
                  if (undo != null)
                    ValueListenableBuilder<UndoHistoryValue>(
                      valueListenable: undo,
                      builder: (context, v, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          icon(
                            'undo',
                            AppIconKind.undo,
                            MdStrings.undo,
                            v.canUndo ? onUndo : null,
                          ),
                          icon(
                            'redo',
                            AppIconKind.redo,
                            MdStrings.redo,
                            v.canRedo ? onRedo : null,
                          ),
                          const SizedBox(width: 6),
                        ],
                      ),
                    ),
                  symbol('heading', '#', '# ', line: true),
                  symbol('list', '-', '- ', line: true),
                  symbol('task', '[ ]', '- [ ] ', line: true),
                  symbol('emphasis', '*', '*'),
                  symbol('code', '`', '`'),
                  symbol('math', r'$', r'$'),
                  symbol('table', '|', '|'),
                  symbol('quote', '>', '> ', line: true),
                  icon('indent', AppIconKind.indent, MdStrings.indent, () {
                    indentLines(controller, indent: true);
                    focusNode.requestFocus();
                  }),
                  icon('outdent', AppIconKind.outdent, MdStrings.outdent, () {
                    indentLines(controller, indent: false);
                    focusNode.requestFocus();
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessoryButton extends StatelessWidget {
  const _AccessoryButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      // Keep the editor's focus (and the keyboard) when a symbol is tapped.
      canRequestFocus: false,
      borderRadius: BorderRadius.circular(StyleTokens.of(context).radiusSmall),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// A fade at the end (or start) of a sideways row while more of it is hidden there: the
/// symbol row does not fit a phone, and a cut-off button alone does not say it scrolls.
class _EdgeFade extends StatefulWidget {
  const _EdgeFade({required this.color, required this.builder});

  /// The row's background (a StyleTokens colour).
  final Color color;
  final Widget Function(ScrollController scroll) builder;

  @override
  State<_EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<_EdgeFade> {
  final ScrollController _scroll = ScrollController();
  bool _before = false;
  bool _after = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onMetrics(ScrollMetrics m) {
    final before = m.extentBefore > 1;
    final after = m.extentAfter > 1;
    if (before != _before || after != _after) {
      // Metrics arrive during layout: update after it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _before = before;
            _after = after;
          });
        }
      });
    }
    return false;
  }

  Widget _fade({required bool start}) => IgnorePointer(
    child: Container(
      key: MarkdownKeys.accessoryFade(start ? 'start' : 'end'),
      width: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: start ? Alignment.centerRight : Alignment.centerLeft,
          end: start ? Alignment.centerLeft : Alignment.centerRight,
          colors: [widget.color.withValues(alpha: 0), widget.color],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _onMetrics(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _onMetrics(n.metrics),
          child: widget.builder(_scroll),
        ),
      ),
      if (_before)
        Positioned(left: 0, top: 0, bottom: 0, child: _fade(start: true)),
      if (_after)
        Positioned(right: 0, top: 0, bottom: 0, child: _fade(start: false)),
    ],
  );
}
