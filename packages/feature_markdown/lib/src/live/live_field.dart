// The live block field and its format toolbar (08-markdown 24.5, 24.7, 24.15 U′6, U′13,
// U′14). The field shows the markdown source of the open block in place, styled like the
// block (heading size, faded markers, monospace code); the toolbar sits under the view,
// above the keyboard, while a block is open.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../markdown_keys.dart';
import '../parse/md_document.dart';
import '../parse/md_model.dart';
import '../render/md_blocks.dart';
import '../render/md_style.dart';
import '../strings_ko.dart';
import 'live_edit.dart';
import 'live_editor.dart';
import 'live_units.dart';

/// What the screen does for keys the field cannot handle alone.
@immutable
final class LiveFieldActions {
  const LiveFieldActions({
    required this.onBackspaceAtStart,
    required this.onMove,
    required this.onCommit,
    required this.onUndo,
    required this.onRedo,
    this.onParagraph,
  });

  /// Enter that starts a new paragraph (or leaves a list on its last line, [leave]):
  /// the field's value to use instead of the default one, or null (24.17 L′1).
  final TextEditingValue? Function(TextEditingValue old, {required bool leave})?
  onParagraph;

  /// Backspace with the caret at offset 0.
  final VoidCallback onBackspaceAtStart;

  /// ↑ on the first line (up = true) / ↓ on the last line.
  final void Function(bool up) onMove;

  /// Esc.
  final VoidCallback onCommit;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
}

class LiveBlockField extends StatelessWidget {
  const LiveBlockField({
    super.key,
    required this.editor,
    required this.actions,
  });

  final LiveEditor editor;
  final LiveFieldActions actions;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final v = editor.field.value;
    final sel = v.selection;
    final k = e.logicalKey;
    final plain =
        !keys.isControlPressed && !keys.isMetaPressed && !keys.isAltPressed;
    if (k == LogicalKeyboardKey.escape) {
      actions.onCommit();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace &&
        plain &&
        sel.isValid &&
        sel.isCollapsed &&
        sel.start == 0 &&
        !v.composing.isValid) {
      actions.onBackspaceAtStart();
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter) &&
        keys.isShiftPressed &&
        plain) {
      editor.shiftEnter();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab && plain && !v.composing.isValid) {
      editor.apply((x) => indentField(x, indent: !keys.isShiftPressed));
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown) &&
        plain &&
        !keys.isShiftPressed &&
        sel.isValid &&
        sel.isCollapsed) {
      final up = k == LogicalKeyboardKey.arrowUp;
      if (_onEdgeLine(up, sel.start)) {
        actions.onMove(up);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// The caret is on the first (last) drawn line of the field.
  bool _onEdgeLine(bool up, int offset) {
    final text = editor.field.text;
    final state = editor.fieldKey.currentState;
    if (state is TextSelectionGestureDetectorBuilderDelegate) {
      final editable = (state as TextSelectionGestureDetectorBuilderDelegate)
          .editableTextKey
          .currentState;
      final render = editable?.renderEditable;
      if (render != null && render.hasSize) {
        final here = render.getLocalRectForCaret(TextPosition(offset: offset));
        final edge = render.getLocalRectForCaret(
          TextPosition(offset: up ? 0 : text.length),
        );
        return (here.center.dy - edge.center.dy).abs() < here.height / 2;
      }
    }
    return up
        ? !text.substring(0, offset).contains('\n')
        : !text.substring(offset).contains('\n');
  }

  @override
  Widget build(BuildContext context) {
    final s = MdStyle.of(context);
    final t = s.tokens;
    final session = editor.session;
    final kind = session?.kind ?? LiveKind.prose;
    final prose = kind == LiveKind.prose;
    editor.field
      ..style = s
      ..kind = kind;
    final base = prose ? s.body : s.codeBlock.copyWith(color: t.textPrimary);
    final unit = session?.unit;
    final nodes = unit == null || unit.block >= session!.doc.blocks.length
        ? const <MdNode>[]
        : session.doc.blocks[unit.block].nodes;
    // A table or a math block is hard to read as source: it is drawn under the field
    // while it is edited (24.17 L′10).
    final preview =
        unit != null &&
        unit.item == null &&
        nodes.length == 1 &&
        (nodes.single is MdTable || nodes.single is MdMathBlock);
    return KeyedSubtree(
      key: MarkdownKeys.liveField,
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.radiusSmall),
          border: Border.all(color: t.accent, width: 1.5),
        ),
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: Actions(
          actions: {
            UndoTextIntent: CallbackAction<UndoTextIntent>(
              onInvoke: (_) {
                actions.onUndo();
                return null;
              },
            ),
            RedoTextIntent: CallbackAction<RedoTextIntent>(
              onInvoke: (_) {
                actions.onRedo();
                return null;
              },
            ),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _textField(context, base, prose, session),
              if (preview)
                _LivePreview(key: MarkdownKeys.livePreview, editor: editor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField(
    BuildContext context,
    TextStyle base,
    bool prose,
    LiveSession? session,
  ) {
    final t = MdStyle.of(context).tokens;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: TextField(
        key: editor.fieldKey,
        controller: editor.field,
        focusNode: editor.focus,
        maxLines: null,
        minLines: 1,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        autocorrect: prose,
        enableSuggestions: prose,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        style: base,
        cursorColor: t.accent,
        scrollPadding: const EdgeInsets.fromLTRB(20, 48, 20, 72),
        inputFormatters: [
          const LineFeedFormatter(),
          LiveEnterFormatter(
            () => editor.session?.kind ?? LiveKind.code,
            onParagraph: actions.onParagraph,
          ),
        ],
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          hintText: session?.range.pending ?? false
              ? MdStrings.livePlaceholder
              : null,
          hintStyle: base.copyWith(color: t.textTertiary),
        ),
      ),
    );
  }
}

/// The open table / math block drawn from the field's text, a moment after typing stops.
class _LivePreview extends StatefulWidget {
  const _LivePreview({super.key, required this.editor});

  final LiveEditor editor;

  @override
  State<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<_LivePreview> {
  List<MdNode> _nodes = const [];
  String? _text;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _parse();
    widget.editor.field.addListener(_onField);
  }

  @override
  void didUpdateWidget(_LivePreview old) {
    super.didUpdateWidget(old);
    if (!identical(old.editor, widget.editor)) {
      old.editor.field.removeListener(_onField);
      widget.editor.field.addListener(_onField);
      _parse();
    }
  }

  void _onField() {
    if (widget.editor.field.text == _text) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(_parse);
    });
  }

  void _parse() {
    final text = widget.editor.field.text;
    _text = text;
    _nodes = [for (final b in parseMarkdown(text).blocks) ...b.nodes];
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.editor.field.removeListener(_onField);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = MdStyle.of(context).tokens;
    if (_nodes.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        padding: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [for (final n in _nodes) MdNodeView(node: n)],
        ),
      ),
    );
  }
}

/// The format toolbar (24.7, 24.15 U′14): most used first, [합치기][완료] pinned at the end.
class LiveToolbar extends StatelessWidget {
  const LiveToolbar({
    super.key,
    required this.editor,
    required this.onJoin,
    required this.onDone,
    this.undo,
    this.onUndo,
    this.onRedo,
  });

  final LiveEditor editor;
  final VoidCallback onJoin;
  final VoidCallback onDone;

  /// Shown on a phone (the top bar has no room for [↶][↷]).
  final ValueListenable<UndoHistoryValue>? undo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final t = StyleTokens.of(context);
    final s = editor.session;
    final prose = s?.kind == LiveKind.prose;
    final headings = prose && !(s?.setext ?? false);
    Widget button(String name, AppIconKind icon, String tip, VoidCallback on) =>
        _ToolButton(
          key: MarkdownKeys.liveToolbarButton(name),
          tooltip: tip,
          onPressed: on,
          child: AppIcon(icon, size: 20, color: t.textPrimary),
        );
    Widget text(String name, String label, String tip, VoidCallback on) =>
        _ToolButton(
          key: MarkdownKeys.liveToolbarButton(name),
          tooltip: tip,
          onPressed: on,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
        );
    void ap(TextEditingValue Function(TextEditingValue) f) {
      editor.apply(f);
      editor.focus.requestFocus();
    }

    final undo = this.undo;
    final row = <Widget>[
      if (undo != null)
        ValueListenableBuilder<UndoHistoryValue>(
          valueListenable: undo,
          builder: (context, v, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolButton(
                key: MarkdownKeys.liveToolbarButton('undo'),
                tooltip: MdStrings.undo,
                onPressed: v.canUndo ? onUndo : null,
                child: AppIcon(
                  AppIconKind.undo,
                  size: 20,
                  color: v.canUndo ? t.textPrimary : t.textTertiary,
                ),
              ),
              _ToolButton(
                key: MarkdownKeys.liveToolbarButton('redo'),
                tooltip: MdStrings.redo,
                onPressed: v.canRedo ? onRedo : null,
                child: AppIcon(
                  AppIconKind.redo,
                  size: 20,
                  color: v.canRedo ? t.textPrimary : t.textTertiary,
                ),
              ),
            ],
          ),
        ),
      if (prose) ...[
        button(
          'task',
          AppIconKind.taskBox,
          MdStrings.liveTask,
          () => ap((v) => toggleLinePrefix(v, LinePrefix.task)),
        ),
        button(
          'bullet',
          AppIconKind.listBullet,
          MdStrings.liveBullet,
          () => ap((v) => toggleLinePrefix(v, LinePrefix.bullet)),
        ),
        button(
          'numbered',
          AppIconKind.listNumbered,
          MdStrings.liveNumbered,
          () => ap((v) => toggleLinePrefix(v, LinePrefix.numbered)),
        ),
        if (headings) ...[
          text(
            'h1',
            'H1',
            MdStrings.liveH1,
            () => ap((v) => toggleLinePrefix(v, LinePrefix.h1)),
          ),
          text(
            'h2',
            'H2',
            MdStrings.liveH2,
            () => ap((v) => toggleLinePrefix(v, LinePrefix.h2)),
          ),
          text(
            'h3',
            'H3',
            MdStrings.liveH3,
            () => ap((v) => toggleLinePrefix(v, LinePrefix.h3)),
          ),
        ],
        button(
          'bold',
          AppIconKind.formatBold,
          MdStrings.liveBold,
          () => ap((v) => toggleWrap(v, '**')),
        ),
        button(
          'italic',
          AppIconKind.formatItalic,
          MdStrings.liveItalic,
          () => ap((v) => toggleWrap(v, '*')),
        ),
        button(
          'strike',
          AppIconKind.formatStrike,
          MdStrings.liveStrike,
          () => ap((v) => toggleWrap(v, '~~')),
        ),
        button(
          'code',
          AppIconKind.inlineCode,
          MdStrings.liveCode,
          () => ap((v) => toggleWrap(v, '`')),
        ),
        button(
          'link',
          AppIconKind.link,
          MdStrings.liveLink,
          () => ap(insertLink),
        ),
        button(
          'quote',
          AppIconKind.quote,
          MdStrings.liveQuote,
          () => ap((v) => toggleLinePrefix(v, LinePrefix.quote)),
        ),
      ],
      button(
        'indent',
        AppIconKind.indent,
        MdStrings.indent,
        () => ap((v) => indentField(v, indent: true)),
      ),
      button(
        'outdent',
        AppIconKind.outdent,
        MdStrings.outdent,
        () => ap((v) => indentField(v, indent: false)),
      ),
      if (prose) ...[
        button(
          'codeBlock',
          AppIconKind.codeBlock,
          MdStrings.liveCodeBlock,
          () => ap((v) => insertTemplate(v, LiveTemplate.codeBlock)),
        ),
        button(
          'mathBlock',
          AppIconKind.math,
          MdStrings.liveMath,
          () => ap((v) => insertTemplate(v, LiveTemplate.mathBlock)),
        ),
        button(
          'table',
          AppIconKind.table,
          MdStrings.liveTable,
          () => ap((v) => insertTemplate(v, LiveTemplate.table)),
        ),
        button(
          'rule',
          AppIconKind.horizontalRule,
          MdStrings.liveRule,
          () => ap((v) => insertTemplate(v, LiveTemplate.rule)),
        ),
      ],
    ];
    return Material(
      key: MarkdownKeys.liveToolbar,
      color: t.toolbar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(6, 0, 24, 0),
                          children: row,
                        ),
                      ),
                      // The row scrolls on a phone: its end fades, so a cut button
                      // reads as 'more this way' (24.17 L′15).
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        width: 24,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  t.toolbar.withValues(alpha: 0),
                                  t.toolbar,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 28, color: t.hairline),
                _ToolButton(
                  key: MarkdownKeys.liveToolbarButton('join'),
                  tooltip: MdStrings.liveJoin,
                  onPressed: onJoin,
                  child: AppIcon(
                    AppIconKind.blockJoin,
                    size: 20,
                    color: t.textPrimary,
                  ),
                ),
                _ToolButton(
                  key: MarkdownKeys.liveToolbarButton('done'),
                  tooltip: MdStrings.liveDone,
                  onPressed: onDone,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(AppIconKind.done, size: 20, color: t.accent),
                      const SizedBox(width: 4),
                      Text(
                        MdStrings.liveDone,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
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
    child: Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onPressed,
        // Keep the field's focus (and the keyboard) when a button is tapped.
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(
          StyleTokens.of(context).radiusSmall,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
      ),
    ),
  );
}
