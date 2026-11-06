// lib/src/text/text_draft_store.dart — m5-7/04-editor 6.11.2 (E2-10b, P-B —
// review S-11), 6.18 (editor.textDraft).
//
// A long text edit session keeps its draft in the EDITOR-internal device key
// editor.textDraft, so that a web tab reloaded under memory pressure (B-13)
// or an app that died does not lose what was written (meeting notes). The
// note still gets its ONE command at the session end (E-6): the draft is
// only a copy, removed once the session's command ran (or none was needed).
//
//   {"v":1,"noteId":…,"pageId":…,"boxId":…,"isNew":…,
//    "draft": TextBoxObject.toJson()}
//
// One key for the device: a session of another note overwrites it. Opening a
// note whose draft is stored offers the banner '저장되지 않은 글이 있어요
// [되살리기] [버리기]'; a draft of another note is ignored (left as it is).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../scope/editor_scope.dart';
import '../state/settings/editor_setting_keys.dart';

/// The stored draft of a text edit session.
@immutable
class TextDraft {
  const TextDraft({
    required this.noteId,
    required this.pageId,
    required this.boxId,
    required this.isNew,
    required this.draft,
  });

  final String noteId, pageId, boxId;

  /// The session edited a new box (not in CORE when the draft was written).
  final bool isNew;
  final core.TextBoxObject draft;

  Map<String, Object?> toJson() => {
    'v': 1,
    'noteId': noteId,
    'pageId': pageId,
    'boxId': boxId,
    'isNew': isNew,
    'draft': draft.toJson(),
  };

  /// null for anything that is not a readable draft (empty / missing keys /
  /// wrong types / a draft that is not a text box) — never throws.
  static TextDraft? fromJson(Map<String, Object?> json) {
    final noteId = json['noteId'];
    final pageId = json['pageId'];
    final boxId = json['boxId'];
    final isNew = json['isNew'];
    final draft = json['draft'];
    if (noteId is! String ||
        pageId is! String ||
        boxId is! String ||
        isNew is! bool ||
        draft is! Map) {
      return null;
    }
    try {
      final object = core.PageObject.fromJson(Map<String, Object?>.from(draft));
      if (object is! core.TextBoxObject) return null;
      return TextDraft(
        noteId: noteId,
        pageId: pageId,
        boxId: boxId,
        isNew: isNew,
        draft: object,
      );
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextDraft &&
          other.noteId == noteId &&
          other.pageId == pageId &&
          other.boxId == boxId &&
          other.isNew == isNew &&
          other.draft == draft;

  @override
  int get hashCode => Object.hash(noteId, pageId, boxId, isNew, draft);

  @override
  String toString() =>
      'TextDraft($boxId on $pageId of $noteId, ${isNew ? 'new' : 'existing'}, '
      '"${draft.text}")';
}

/// Per note (scoped — editorTextDraftStoreProvider).
class TextDraftStore {
  TextDraftStore({
    required this.settings,
    required this.noteId,
    this.interval = writeInterval,
  });

  /// The draft is written at most this often while it changes (6.11.2).
  static const Duration writeInterval = Duration(seconds: 5);

  final core.SettingsRepository settings;
  final String noteId;
  final Duration interval;

  Timer? _timer;
  TextDraft? _pending;
  bool _wrote = false; // this session's draft is in the key
  bool _disposed = false;
  Future<void> _queue = Future<void>.value();

  /// A write is waiting for its timer.
  bool get isPending => _timer != null;

  /// The session's draft changed. It is written [interval] after the first
  /// change not yet written — once, with the latest draft; changes in the
  /// meantime do not move the time (so a session typed without a pause is
  /// still kept every [interval]).
  void changed({
    required String pageId,
    required String boxId,
    required bool isNew,
    required core.TextBoxObject draft,
  }) {
    if (_disposed) return;
    _pending = TextDraft(
      noteId: noteId,
      pageId: pageId,
      boxId: boxId,
      isNew: isNew,
      draft: draft,
    );
    _timer ??= Timer(interval, _write);
  }

  void _write() {
    _timer = null;
    final draft = _pending;
    _pending = null;
    if (_disposed || draft == null) return;
    _wrote = true;
    _enqueue(
      () => settings.set(EditorSettingKeys.textDraft, draft.toJson()),
      'while keeping the text draft',
    );
  }

  /// The session ended and its command ran (or none was needed): the
  /// pending write is dropped and the key is removed when this session wrote
  /// it (a draft another note or an earlier run left stays). Completes after
  /// the removal.
  Future<void> sessionEnded() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    if (!_wrote) return _queue;
    _wrote = false;
    return _enqueue(
      () => settings.reset(EditorSettingKeys.textDraft),
      'while removing the text draft',
    );
  }

  /// The draft of this note left by an earlier session (a reload, a crash),
  /// or null: none, another note's, unreadable.
  Future<TextDraft?> load() async {
    try {
      final json = await settings.get(EditorSettingKeys.textDraft);
      final draft = TextDraft.fromJson(json);
      return draft != null && draft.noteId == noteId ? draft : null;
    } on Object catch (error, stack) {
      _report(error, stack, 'while reading the text draft');
      return null;
    }
  }

  /// Restore / discard: removes the key if it still holds [draft] (a session
  /// opened since may have overwritten it — then it stays). Completes after
  /// the removal.
  Future<void> remove(TextDraft draft) => _enqueue(() async {
    final stored = TextDraft.fromJson(
      await settings.get(EditorSettingKeys.textDraft),
    );
    if (stored == draft) await settings.reset(EditorSettingKeys.textDraft);
  }, 'while removing the text draft');

  Future<void> _enqueue(Future<void> Function() op, String what) =>
      _queue = _queue.then((_) async {
        try {
          await op();
        } on Object catch (error, stack) {
          _report(error, stack, what);
        }
      });

  static void _report(Object error, StackTrace stack, String what) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription(what),
      ),
    );
  }

  /// Drops a waiting write (the screen is gone; the session's end already
  /// removed the key, or the app is going away and the last written draft
  /// stays).
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}

/// (6.19) The note's text draft store.
final editorTextDraftStoreProvider = Provider<TextDraftStore>(
  (ref) {
    final store = TextDraftStore(
      settings: ref.watch(core.settingsRepositoryProvider),
      noteId: ref.watch(editorNoteIdProvider),
    );
    ref.onDispose(store.dispose);
    return store;
  },
  dependencies: [editorNoteIdProvider],
  name: 'editorTextDraftStoreProvider',
);
