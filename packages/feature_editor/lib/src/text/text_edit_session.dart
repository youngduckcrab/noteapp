// lib/src/text/text_edit_session.dart — m5-7/04-editor 6.11.2, 6.11.5
// (E2-01: the minimal session — new box and existing box, one command at the
// end, end reasons. The router-side ends come in E2-10).
//
// E-6: one edit session = at most one command = one undo step. While the
// session runs, the existing box is hidden on its INK page controller (the
// editor overlay shows the text), and in sheet mode a same-id preview of the
// draft is drawn on the canvas (preview wins over hidden — 7.2.9 (v2.1)).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../scope/editor_scope.dart';
import '../state/settings/editor_device_state.dart';

@immutable
class TextEditState {
  const TextEditState({
    required this.pageId,
    required this.boxId,
    required this.original,
    required this.draft,
    required this.isNew,
    required this.mode,
  });
  final String pageId, boxId;

  /// null for a new box (not in CORE yet).
  final core.TextBoxObject? original;

  /// frame / text / style being edited.
  final core.TextBoxObject draft;
  final bool isNew;

  /// inline on native; 6.11.6 on web.
  final WebTextInputMode mode;

  TextEditState withDraft(core.TextBoxObject draft) => TextEditState(
    pageId: pageId,
    boxId: boxId,
    original: original,
    draft: draft,
    isNew: isNew,
    mode: mode,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextEditState &&
          other.pageId == pageId &&
          other.boxId == boxId &&
          other.original == original &&
          other.draft == draft &&
          other.isNew == isNew &&
          other.mode == mode;

  @override
  int get hashCode => Object.hash(pageId, boxId, original, draft, isNew, mode);

  @override
  String toString() =>
      'TextEditState($boxId on $pageId, ${isNew ? 'new' : 'existing'}, '
      '${mode.name}, "${draft.text}")';
}

/// (revision 1, review M-1) The ids INK must hide — derived from EDITOR
/// state: existing box → {boxId} in every mode (E-6); new box → {}. Sheet
/// mode ALSO puts a same-id preview, which is drawn although the id is
/// hidden (preview wins — 7.2.9 v2.1).
Set<String> hiddenIdsOf(TextEditState? state) =>
    state == null || state.isNew ? const {} : {state.boxId};

/// The preview objects of a session: the draft in sheet mode, else none.
List<core.PageObject> previewObjectsOf(TextEditState? state) =>
    state != null && state.mode == WebTextInputMode.sheet
    ? [state.draft]
    : const [];

enum TextEditEndReason {
  /// pen / mouse contact on the canvas (router, 6.3.6 step 3)
  penContact,

  /// one-finger tap confirmed on the canvas (router, 6.3.5 ⓪)
  canvasTap,

  /// finger long-press action ran (router, 6.3.4)
  longPress,

  /// pointer down outside the editor tap group: toolbar, panel, sheet, app bar
  tapOutside,

  /// the editor FocusNode lost focus: iPad keyboard 'hide', system focus
  /// move, another text field (revision 1, review M-2). Never a canvas
  /// pointer down: EditorCanvasFocus does not request focus during a session
  /// (6.11.3, revision 2 — E2-10)
  focusLost,
  escape,
  toolChange,
  undoRedo,
  pageUnmounted,
  leaving,
  appHidden,

  /// (sheet mode) the panel's [완료] (6.11.6 A)
  done,
}

/// The one command of a session end (6.11.5 table), or null when there is
/// nothing to store. [finalDraft] is the draft with its measured height;
/// [loaded] is the synchronous check `session.pageIfLoaded(pageId)
/// ?.objectById(boxId)` made right before the command (review S-1): null
/// means the original was deleted remotely (or never stored). [newId] and
/// [now] give a new box its id and createdAt when an edited original is gone.
core.EditCommand? textSessionCommand(
  TextEditState state,
  core.TextBoxObject finalDraft, {
  required core.PageObject? loaded,
  required String Function() newId,
  required core.EpochMillis now,
}) {
  final empty = finalDraft.text.trim().isEmpty;
  if (state.isNew) {
    return empty
        ? null
        : core.AddObjects(pageId: state.pageId, objects: [finalDraft]);
  }
  final original = state.original;
  if (empty) {
    // Remove the box; nothing to do when it is already gone.
    return loaded == null
        ? null
        : core.RemoveElements(pageId: state.pageId, elementIds: [state.boxId]);
  }
  final unchanged =
      original != null &&
      original.text == finalDraft.text &&
      original.style == finalDraft.style &&
      original.frame.rect.width == finalDraft.frame.rect.width;
  if (unchanged) return null;
  if (loaded == null) {
    // The original vanished while editing: keep what was written as a new box.
    return core.AddObjects(
      pageId: state.pageId,
      objects: [
        finalDraft.copyTo(id: newId(), pageId: state.pageId, createdAt: now),
      ],
    );
  }
  return core.UpdateObjects(pageId: state.pageId, objects: [finalDraft]);
}

/// [draft] with frame height = [measured] (at least one line —
/// fontSizePt × lineHeight); the unrotated top-left and width stay.
core.TextBoxObject withHeight(core.TextBoxObject draft, double measured) {
  final r = draft.frame.rect;
  final oneLine = draft.style.fontSizePt * draft.style.lineHeight;
  final height = measured > oneLine ? measured : oneLine;
  return draft.copyWith(
    frame: core.ElementFrame(
      core.PageRect.fromLTWH(r.left, r.top, r.right - r.left, height),
      rotation: draft.frame.rotation,
    ),
  );
}

/// Per note (scoped). One session per note; starting a new one ends the
/// previous one first.
class TextEditNotifier extends Notifier<TextEditState?> {
  /// Tests: treat the platform as web (the mode then follows
  /// EditorDeviceState.webTextInput). Reset to null in tearDown.
  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get _isWeb => debugIsWebOverride ?? kIsWeb;

  TextEditEndReason? _lastEndReason;

  /// The reason of the last session end (the first one wins).
  TextEditEndReason? get lastEndReason => _lastEndReason;

  Future<void> _ending = Future<void>.value();

  /// Completes when the last started end has run its command.
  Future<void> get ending => _ending;

  @override
  TextEditState? build() {
    ref.watch(editorSessionValueProvider);
    return null;
  }

  /// The input mode a new session uses (6.11.6): inline on native, the
  /// developer choice on the web (textarea falls back to inline until E2-11).
  WebTextInputMode get modeForNewSession {
    if (!_isWeb) return WebTextInputMode.inline;
    final mode = ref.read(editorDeviceStateProvider).webTextInput;
    return mode == WebTextInputMode.textarea ? WebTextInputMode.inline : mode;
  }

  /// Opens a session on [box] (a new box: not in CORE yet). Applies
  /// [hiddenIdsOf] (and the sheet preview) to the page controller.
  void start(core.TextBoxObject box, {required bool isNew}) {
    if (state != null) unawaited(end(reason: TextEditEndReason.tapOutside));
    unawaited(_loadFonts());
    final next = TextEditState(
      pageId: box.pageId,
      boxId: box.id,
      original: isNew ? null : box,
      draft: _measuredSync(box) ?? box,
      isNew: isNew,
      mode: modeForNewSession,
    );
    state = next;
    _apply(next);
  }

  /// Draft only — not a command. [text] is TextEditingController.text, which
  /// includes the characters still being composed (V1).
  void updateText(String text) {
    final s = state;
    if (s == null || s.draft.text == text) return;
    _setDraft(s, s.draft.copyWith(text: text));
  }

  void updateStyle(core.TextBoxStyle style) {
    final s = state;
    if (s == null || s.draft.style == style) return;
    _setDraft(s, s.draft.copyWith(style: style));
  }

  void updateWidth(double widthPt) {
    final s = state;
    if (s == null) return;
    final r = s.draft.frame.rect;
    final width = widthPt < 40 ? 40.0 : widthPt;
    _setDraft(
      s,
      s.draft.copyWith(
        frame: core.ElementFrame(
          core.PageRect.fromLTWH(r.left, r.top, width, r.bottom - r.top),
          rotation: s.draft.frame.rotation,
        ),
      ),
    );
  }

  void _setDraft(TextEditState s, core.TextBoxObject draft) {
    final next = s.withDraft(_measuredSync(draft) ?? draft);
    state = next;
    if (next.mode == WebTextInputMode.sheet) _apply(next);
  }

  /// Ends the session exactly once (idempotent — the first reason wins):
  /// measures the final height, runs at most ONE command (6.11.5), clears
  /// the hidden ids right after it (same frame). Completes after the command
  /// ran.
  Future<void> end({required TextEditEndReason reason}) {
    final s = state;
    if (s == null) return _ending;
    _lastEndReason = reason;
    state = null;
    final commands = ref.read(editorCommandsProvider);
    final pages = ref.read(editorMountedPagesProvider);
    final session = ref.read(editorSessionValueProvider);
    final ids = ref.read(core.idGeneratorProvider);
    final clock = ref.read(core.clockProvider);
    void finish(core.TextBoxObject finalDraft) {
      final command = textSessionCommand(
        s,
        finalDraft,
        loaded: session.pageIfLoaded(s.pageId)?.objectById(s.boxId),
        newId: ids.newId,
        now: clock.now().millisecondsSinceEpoch,
      );
      if (command != null) {
        commands.runTextSession(command, text: finalDraft.text);
      }
      _clear(pages, s.pageId);
    }

    final sync = _measuredSync(s.draft);
    if (sync != null) {
      finish(sync);
      return _ending = Future<void>.value();
    }
    return _ending = () async {
      core.TextBoxObject measured;
      try {
        final size = await ink.InkTextLayout.measure(
          s.draft.text,
          s.draft.style,
          widthPt: s.draft.frame.rect.width,
        ).timeout(const Duration(seconds: 2));
        measured = withHeight(s.draft, size.height);
      } on Object {
        measured = s.draft; // 6.21: the last rendered height
      }
      finish(measured);
    }();
  }

  core.TextBoxObject? _measuredSync(core.TextBoxObject draft) {
    final size = ink.InkTextLayout.measureSync(
      draft.text,
      draft.style,
      widthPt: draft.frame.rect.width,
    );
    return size == null ? null : withHeight(draft, size.height);
  }

  void _apply(TextEditState s) {
    final controller = ref
        .read(editorMountedPagesProvider)[s.pageId]
        ?.controller;
    if (controller == null) return;
    controller
      ..setHiddenObjectIds(hiddenIdsOf(s))
      ..setPreviewObjects(previewObjectsOf(s));
  }

  static void _clear(MountedPages pages, String pageId) {
    final controller = pages[pageId]?.controller;
    if (controller == null) return;
    controller
      ..setHiddenObjectIds(const {})
      ..setPreviewObjects(const []);
  }

  static Future<void> _loadFonts() async {
    try {
      await ink.InkFonts.ensureLoaded();
    } on Object {
      // 6.21: edit with the system font; INK paints by its own rule.
    }
  }
}

final editorTextEditProvider =
    NotifierProvider<TextEditNotifier, TextEditState?>(
      TextEditNotifier.new,
      dependencies: [
        editorSessionValueProvider,
        editorMountedPagesProvider,
        editorCommandsProvider,
      ],
      name: 'editorTextEditProvider',
    );
