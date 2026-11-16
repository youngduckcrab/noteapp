// lib/src/text/text_box_editor.dart — m5-7/04-editor 6.11.3, 6.11.5, 6.11.6
// (E2-01: the inline overlay and the text field both input modes share).
//
// TextBoxEditorLayer is a sibling ABOVE the page area's input Listener
// (page_viewport.dart — where SelectionMenu sits), so a finger or a pen on
// the editor reaches only the TextField, never the input router. In the
// inline mode it places a material_ui TextField on the session's draft
// frame: Positioned at the frame's unrotated top-left on screen, then
// scale(camera.scale) and a rotation about the frame centre. The field
// itself is laid out in page pt (width = frame width, text = fontSizePt), so
// it wraps exactly as INK will paint the box; its text style and strut are
// INK's own (InkTextLayout.textStyleOf / strutStyleOf, CP-INK-3) with zero
// inner padding, so nothing jumps when the session ends (E-6, B-15).
//
// Ends from here: a pointer down outside the editor's tap group (onTapOutside
// → tapOutside — (E2-10) the canvas is in the group while a session is open,
// its ends come from the router: InteractionHost), the field losing the
// focus after having had it (focusLost — not while FocusManager suspends it
// for an inactive app), Esc (escape), and the session's page leaving the
// mounted pages (pageUnmounted).
//
// (E2-10 part 2) The format bar over (or under) the box (6.11.4 — a change
// goes to the draft and ToolOptions.textStyle), and the keyboard: when the
// iPad keyboard covers the box's bottom at the session start or when its
// height changes, the page scrolls just that much (6.11.3).
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../scope/editor_scope.dart';
import '../state/settings/editor_device_state.dart';
import '../tools/tool_options.dart';
import '../ui/editor_strings.dart';
import '../ui/text/text_style_controls.dart';
import '../viewport/viewport_controller.dart';
import 'text_edit_session.dart';

/// The key of the session's TextField (both modes — appendix C).
const textEditorKey = ValueKey('editor.textEditor');

/// The focus node of a session's TextField: EditorCanvasFocus takes the
/// focus back from it when the session has ended (6.11.3 '캔버스 포커스 양보').
class TextSessionFocusNode extends FocusNode {
  TextSessionFocusNode() : super(debugLabel: 'TextBoxEditor');
}

/// TextAlign of a box alignment.
TextAlign textAlignOf(core.TextAlignKind align) => switch (align) {
  core.TextAlignKind.start => TextAlign.start,
  core.TextAlignKind.center => TextAlign.center,
  core.TextAlignKind.end => TextAlign.end,
};

/// The session's TextField with its controller and focus node (one per
/// session — key it by the box id). Text changes go to
/// TextEditNotifier.updateText (draft only — controller.text includes the
/// characters still being composed, V1); a pointer down outside the tap
/// group, a focus loss after having had the focus and Esc end the session.
/// The IME composing range is closed (clearComposing) before an end.
class TextSessionField extends ConsumerStatefulWidget {
  const TextSessionField({
    super.key,
    required this.initialText,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.expands = false,
  });

  final String initialText;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;

  /// Fill the parent's height (sheet mode); else grow with the text.
  final bool expands;

  @override
  ConsumerState<TextSessionField> createState() => _TextSessionFieldState();
}

class _TextSessionFieldState extends ConsumerState<TextSessionField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final FocusNode _focus = TextSessionFocusNode();
  bool _hadFocus = false;
  late final _limit = _NotifyingLengthLimit(
    core.PageObjectLimits.maxTextLength,
    onTruncated: () => ref
        .read(editorCommandsProvider)
        .notify(EditorStrings.textTooLong(core.PageObjectLimits.maxTextLength)),
  );

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    // autofocus only acts when nothing else asked for the focus in the same
    // frame (a closing menu restores its own) — ask once more after it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) _focus.requestFocus();
    });
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _hadFocus = true;
    } else if (_hadFocus && !_suspended) {
      _end(TextEditEndReason.focusLost);
    }
  }

  /// (E2-10) The app is not resumed: FocusManager suspends the primary focus
  /// while the app is inactive (control centre, app switcher) and gives it
  /// back on resume — not a focus loss. Hiding the app ends the session
  /// (appHidden — EditorBody's AppLifecycleListener).
  static bool get _suspended {
    final state = WidgetsBinding.instance.lifecycleState;
    return state != null && state != AppLifecycleState.resumed;
  }

  void _end(TextEditEndReason reason) {
    final notifier = ref.read(editorTextEditProvider.notifier);
    if (ref.read(editorTextEditProvider) == null) return;
    _controller.clearComposing();
    notifier
      ..updateText(_controller.text)
      ..end(reason: reason);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _end(TextEditEndReason.escape);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(editorTextEditProvider.notifier);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: TextField(
        key: textEditorKey,
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        maxLines: null,
        minLines: widget.expands ? null : 1,
        expands: widget.expands,
        keyboardType: TextInputType.multiline,
        // contentPadding == EdgeInsets.zero (V6 ①).
        decoration: const InputDecoration.collapsed(hintText: null),
        style: widget.style,
        strutStyle: widget.strutStyle,
        textAlign: widget.textAlign,
        textAlignVertical: widget.expands ? TextAlignVertical.top : null,
        cursorColor: StyleTokens.of(context).paperAccent,
        // No outer Scrollable; keeps a second scroll from happening (6.11.3).
        scrollPadding: EdgeInsets.zero,
        // 10,000 characters (6.11.5); cut text → '글자는 10,000자까지…'.
        inputFormatters: [_limit],
        onChanged: notifier.updateText,
        // groupId: the default (EditableText) — Flutter's selection handles
        // and toolbar are wrapped in a TextFieldTapRegion of this group, so
        // touching them is "inside" (V6 ④).
        onTapOutside: (_) => _end(TextEditEndReason.tapOutside),
      ),
    );
  }
}

/// LengthLimitingTextInputFormatter that also tells when it cut the text
/// (a paste over the limit — the notice of 6.11.2).
class _NotifyingLengthLimit extends LengthLimitingTextInputFormatter {
  _NotifyingLengthLimit(int super.maxLength, {required this.onTruncated});

  final VoidCallback onTruncated;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final out = super.formatEditUpdate(oldValue, newValue);
    if (out.text.length < newValue.text.length) onTruncated();
    return out;
  }
}

/// The format bar's change during a session: the draft (no command) and
/// ToolOptions.textStyle (the next box starts with it — 6.2.4).
void applySessionStyle(WidgetRef ref, core.TextBoxStyle style) {
  ref.read(editorTextEditProvider.notifier).updateStyle(style);
  ref.read(editorToolOptionsProvider.notifier).setTextStyle(style);
}

/// The inline editor over the session's box (6.11.3) and its format bar
/// (6.11.4). Nothing outside a session or in sheet mode (the sheet panel is
/// TextInputSheet).
class TextBoxEditorLayer extends ConsumerWidget {
  const TextBoxEditorLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(editorTextEditProvider);
    if (session == null || session.mode != WebTextInputMode.inline) {
      return const SizedBox.shrink();
    }
    final viewport = ref.watch(editorViewportProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    final style = session.draft.style;
    final field = TextSessionField(
      key: ValueKey('editor.textEditor.${session.boxId}'),
      initialText: session.draft.text,
      style: ink.InkTextLayout.textStyleOf(style),
      strutStyle: ink.InkTextLayout.strutStyleOf(style),
      textAlign: textAlignOf(style.align),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([viewport, pages]),
      builder: (context, child) {
        final index = viewport.pages.indexWhere((p) => p.id == session.pageId);
        if (index < 0 || pages[session.pageId] == null) {
          _endWhenUnmounted(context, ref, session);
          return const SizedBox.shrink();
        }
        final draft = session.draft;
        final r = draft.frame.rect;
        final w = r.right - r.left;
        final h = r.bottom - r.top;
        final topLeft = viewport.pageToScreen(index, Offset(r.left, r.top));
        final background = draft.style.backgroundArgb;
        final bounds = _boundsOnScreen(viewport, index, draft);
        final inset = MediaQuery.viewInsetsOf(context).bottom;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // (6.11.3) the keyboard covering the box → scroll that much.
            Positioned.fill(
              child: IgnorePointer(
                child: _KeyboardReveal(
                  boxId: session.boxId,
                  inset: inset,
                  viewportHeight: viewport.viewportSize.height,
                  bottom: bounds.bottom,
                  onReveal: viewport.panBy,
                ),
              ),
            ),
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              child: Transform(
                transform: editorTransformOf(
                  scale: viewport.camera.scale,
                  widthPt: w,
                  heightPt: h,
                  rotation: draft.frame.rotation,
                ),
                child: SizedBox(
                  width: w,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: h),
                    child: background == null
                        ? child
                        : ColoredBox(color: Color(background), child: child),
                  ),
                ),
              ),
            ),
            // (6.11.4) above the box, below it when there is no room.
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: FormatBarLayout(bounds),
                child: TextFormatBar(
                  style: draft.style,
                  onChanged: (style) => applySessionStyle(ref, style),
                ),
              ),
            ),
          ],
        );
      },
      child: field,
    );
  }

  /// The screen bounds of [draft]'s (possibly rotated) frame.
  static Rect _boundsOnScreen(
    ViewportController viewport,
    int index,
    core.TextBoxObject draft,
  ) {
    final points = [
      for (final c in draft.frame.corners)
        viewport.pageToScreen(index, Offset(c.x, c.y)),
    ];
    var rect = Rect.fromPoints(points.first, points.first);
    for (final p in points.skip(1)) {
      rect = rect.expandToInclude(Rect.fromPoints(p, p));
    }
    return rect;
  }

  /// The session's page left the mounted pages: end it after this frame
  /// (6.11.3 — pageUnmounted), unless another session started meanwhile.
  static void _endWhenUnmounted(
    BuildContext context,
    WidgetRef ref,
    TextEditState session,
  ) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final now = ref.read(editorTextEditProvider);
      if (now == null || now.boxId != session.boxId) return;
      if (ref.read(editorMountedPagesProvider)[session.pageId] != null) return;
      ref
          .read(editorTextEditProvider.notifier)
          .end(reason: TextEditEndReason.pageUnmounted);
    });
  }
}

/// Page pt (the editor's own layout, origin = the frame's unrotated
/// top-left) → screen offset from that top-left on screen: rotate by
/// [rotation] about the frame centre (widthPt / 2, heightPt / 2), then scale
/// by the camera [scale].
Matrix4 editorTransformOf({
  required double scale,
  required double widthPt,
  required double heightPt,
  required double rotation,
}) {
  final scaled = Matrix4.diagonal3Values(scale, scale, 1);
  if (rotation == 0) return scaled;
  final cx = widthPt / 2, cy = heightPt / 2;
  return scaled
      .multiplied(Matrix4.translationValues(cx, cy, 0))
      .multiplied(Matrix4.rotationZ(rotation))
      .multiplied(Matrix4.translationValues(-cx, -cy, 0));
}

/// (6.11.3) When the keyboard covers the box's bottom ([bottom], viewport
/// px) — checked after the session's first frame and whenever the keyboard
/// changes: the [inset] this layer still sees (logical px), or the viewport
/// height when the Scaffold shrank the body for the keyboard — [onReveal]
/// scrolls by just that much (+ 16 px; the wheel direction of
/// ViewportController.panBy). Fills the layer so its own global origin is
/// the viewport's.
class _KeyboardReveal extends StatefulWidget {
  const _KeyboardReveal({
    required this.boxId,
    required this.inset,
    required this.viewportHeight,
    required this.bottom,
    required this.onReveal,
  });

  final String boxId;
  final double inset;
  final double viewportHeight;
  final double bottom;
  final void Function(Offset screenDelta) onReveal;

  /// Room kept between the box and the keyboard (px).
  static const double margin = 16;

  @override
  State<_KeyboardReveal> createState() => _KeyboardRevealState();
}

class _KeyboardRevealState extends State<_KeyboardReveal> {
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_KeyboardReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boxId != widget.boxId ||
        oldWidget.inset != widget.inset ||
        oldWidget.viewportHeight != widget.viewportHeight) {
      _schedule();
    }
  }

  void _schedule() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final screen = MediaQuery.sizeOf(context).height;
      final visibleBottom = math.min(
        box.size.height,
        screen - widget.inset - top,
      );
      final covered = widget.bottom + _KeyboardReveal.margin - visibleBottom;
      if (covered > 0) widget.onReveal(Offset(0, covered));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
