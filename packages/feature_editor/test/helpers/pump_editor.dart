// test/helpers/pump_editor.dart — 04-editor 9.1 (E-01); (v2) m5-7/04-editor
// 8.2 E2-00: page objects and recordings in the seeded note, the fake audio
// ports, the image slot and the Pencil source.
//
// The handles cover the store, the seeded note, the session (and its
// recorder), the per-note provider container, the pointer driver, the
// viewport controller and the mounted pages' INK controllers (E-04).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/document/mounted_pages.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:feature_editor/src/viewport/viewport_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import 'fake_image_importer.dart';
import 'fake_stylus_extras.dart';
import 'pointer_driver.dart';
import 'recording_note_session.dart';

/// Page id of page [index] of the note seeded with [seedKey] (unique per
/// pumpEditor call, so one store can hold several seeded notes).
core.PageId seededPageId(String seedKey, int index) => '$seedKey-p$index';

int _seedCount = 0;

/// (v2) A recording of the seeded note (an audio asset + a Recording row).
/// Strokes link to it through Stroke.recordingId / recordingOffsetMs.
final class RecordingSeed {
  const RecordingSeed({
    required this.id,
    this.durationMs = 60000,
    this.startedAt = 1000,
    this.title,
  });
  final core.RecordingId id;
  final int durationMs;
  final core.EpochMillis startedAt;

  /// e.g. '복구된 녹음' (a recovered recording — 6.15.3).
  final String? title;
}

/// Pumps EditorScreen inside material_ui MaterialApp + ProviderScope with
/// core.noteStoreProvider = createFakeNoteStore() (or [store]) and a seeded note.
/// Default view: iPad Pro 13" portrait, logical 1032×1376 at DPR 2 (contract 7.4.8);
/// resets the view in addTearDown.
///
/// The note has [pages] blank pages of [pageSize] (A4 portrait by default)
/// with ids [seededPageId]; the strokes of
/// [strokesByPageIndex] are added through the session with their page id set
/// to that page (ids kept), then the history is cleared, so the screen opens
/// with `undoDepth == 0`. A store created here is closed in a tear-down; a
/// store passed in is the caller's to close.
///
/// [settings] is written to the two CORE settings keys before pumping. After
/// the session opens, the helper pumps until the viewport has its size and
/// the mounted pages are loaded (no fake time passes), unless [settle] is
/// false (then only the session is open).
Future<EditorTestHandles> pumpEditor(
  WidgetTester tester, {
  core.NoteStore? store, // default: core.createFakeNoteStore()
  String title = '테스트 노트',
  int pages = 3, // A4 blank pages of the seeded note
  core.PageSize pageSize = core.PageSize.a4Portrait, // of every seeded page
  Map<int, List<core.Stroke>> strokesByPageIndex = const {},
  // (v2) page objects per page index; an object whose pageId is not the
  // seeded page id is moved there (copyTo keeps its id and createdAt).
  Map<int, List<core.PageObject>> objectsByPageIndex = const {},
  // (v2) recordings of the seeded note (Recording rows + audio assets).
  List<RecordingSeed> recordings = const [],
  // (v2) override the audio ports with CORE's fakes (handles.audioRecorder /
  // handles.audioPlayback); FakeAudioRecorder uses the store.
  bool fakeAudio = false,
  // (v2) the image slot (editorImageImporterProvider) — see FakeImageImporter.
  FakeImageImporter Function(core.NoteStore store)? imageImporter,
  // (v2) the Pencil source (stylusExtrasProvider).
  FakeStylusExtras? stylusExtras,
  // (v2) the extension slots (editorExtensionsProvider).
  EditorExtensions? extensions,
  EditorSettings? settings, // written to the CORE keys before pumping
  // (v2, E2-10b) runs after the note is seeded, before the screen opens —
  // e.g. a text draft an earlier run left in editor.textDraft.
  Future<void> Function(
    core.NoteStore store,
    core.NoteId noteId,
    core.PageId Function(int index) pageId,
  )?
  beforePump,
  bool settle = true,
  List<Override> overrides = const [], // e.g. syncBadgeProvider
  Size logicalSize = const Size(1032, 1376),
  String? initialPageId,
  // (v2) initialPageId = the seeded page at this index (wins over
  // initialPageId).
  int? initialPageIndex,
  // (v2) EditorScreen.initialFocusRectPt (6.16 — with initialPageId).
  Rect? initialFocusRectPt,
  VoidCallback? onClose,
  VoidCallback? onOpenSettings,
  // (v2.14-ui) the MaterialApp theme (e.g. ui_kit buildStyleTheme); null =
  // the default Material theme.
  ThemeData? theme,
  bool recordSession = true, // wrap the CORE session in RecordingNoteSession
}) async {
  if (pages < 1) throw ArgumentError.value(pages, 'pages', 'must be >= 1');
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = logicalSize * 2;
  addTearDown(tester.view.reset);

  final ownStore = store == null;
  final s = store ?? createFakeNoteStore();
  if (ownStore) addTearDown(s.close);

  final seedKey = 'seed${++_seedCount}';
  final noteId = await _seedNote(
    s,
    seedKey,
    title,
    pages,
    pageSize,
    strokesByPageIndex,
    objectsByPageIndex,
  );
  for (final r in recordings) {
    final asset = await s.assets.put(
      Uint8List.fromList(utf8.encode('audio of ${r.id}')),
      type: core.AssetType.audio,
      mimeType: 'audio/webm',
    );
    await s.recordings.createRecording(
      id: r.id,
      noteId: noteId,
      assetId: asset.id,
      durationMs: r.durationMs,
      startedAt: r.startedAt,
      title: r.title,
    );
  }
  final audioRecorder = fakeAudio ? FakeAudioRecorder(store: s) : null;
  final audioPlayback = fakeAudio ? FakeAudioPlayback() : null;
  final importer = imageImporter?.call(s);
  if (settings != null) {
    await s.settings.set(
      EditorSettingKeys.deviceSettings,
      settings.toJson(core.SettingScope.device),
    );
    await s.settings.set(
      EditorSettingKeys.syncedSettings,
      settings.toJson(core.SettingScope.synced),
    );
  }

  if (beforePump != null) {
    await beforePump(s, noteId, (index) => seededPageId(seedKey, index));
  }

  RecordingNoteSession? recorder;
  final handles = EditorTestHandles._(
    tester,
    () => recorder,
    store: s,
    noteId: noteId,
    seedKey: seedKey,
    driver: PointerDriver(tester),
    audioRecorder: audioRecorder,
    audioPlayback: audioPlayback,
    imageImporter: importer,
    stylusExtras: stylusExtras,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        core.noteStoreProvider.overrideWithValue(s),
        if (recordSession)
          core.noteSessionProvider.overrideWith((ref, id) async {
            // Same life cycle as CORE's provider: open on first listen,
            // close (one reference) on dispose.
            var disposed = false;
            core.NoteSession? opened;
            ref.onDispose(() {
              disposed = true;
              final o = opened;
              if (o != null) unawaited(o.close());
            });
            final inner = await s.openSession(id);
            if (disposed) {
              unawaited(inner.close());
            } else {
              opened = inner;
            }
            final wrapped = RecordingNoteSession(inner);
            if (id == noteId) recorder = wrapped;
            return wrapped;
          }),
        if (audioRecorder != null)
          core.audioRecorderServiceProvider.overrideWithValue(audioRecorder),
        if (audioPlayback != null)
          core.audioPlaybackServiceProvider.overrideWithValue(audioPlayback),
        if (importer != null)
          editorImageImporterProvider.overrideWithValue(importer.importer),
        if (stylusExtras != null)
          stylusExtrasProvider.overrideWithValue(stylusExtras),
        if (extensions != null)
          editorExtensionsProvider.overrideWithValue(extensions),
        ...overrides,
      ],
      child: MaterialApp(
        theme: theme,
        home: EditorScreen(
          key: ValueKey(noteId),
          noteId: noteId,
          initialPageId: initialPageIndex == null
              ? initialPageId
              : seededPageId(seedKey, initialPageIndex),
          initialFocusRectPt: initialFocusRectPt,
          onClose: () {
            handles.closeCount++;
            onClose?.call();
          },
          onOpenSettings: onOpenSettings,
        ),
      ),
    ),
  );
  // The fake store opens the session after a microtask; one pump shows it.
  await tester.pump();
  if (settle) await handles.settlePages();
  return handles;
}

Future<core.NoteId> _seedNote(
  core.NoteStore store,
  String key,
  String title,
  int pages,
  core.PageSize pageSize,
  Map<int, List<core.Stroke>> strokesByPageIndex,
  Map<int, List<core.PageObject>> objectsByPageIndex,
) async {
  for (final (name, keys) in [
    ('strokesByPageIndex', strokesByPageIndex.keys),
    ('objectsByPageIndex', objectsByPageIndex.keys),
  ]) {
    for (final index in keys) {
      if (index < 0 || index >= pages) {
        throw ArgumentError.value(index, name, 'no such page');
      }
    }
  }
  final note = await store.library.createNote(
    title: title,
    pages: [
      for (var i = 0; i < pages; i++)
        core.PageDraft(
          id: seededPageId(key, i),
          size: pageSize,
          background: const core.BlankBackground(),
        ),
    ],
  );
  if (strokesByPageIndex.values.every((s) => s.isEmpty) &&
      objectsByPageIndex.values.every((o) => o.isEmpty)) {
    return note.id;
  }

  final session = await store.openSession(note.id);
  try {
    for (var index = 0; index < pages; index++) {
      final strokes = strokesByPageIndex[index] ?? const <core.Stroke>[];
      final objects = objectsByPageIndex[index] ?? const <core.PageObject>[];
      if (strokes.isEmpty && objects.isEmpty) continue;
      final pageId = seededPageId(key, index);
      await session.openPage(pageId);
      if (strokes.isNotEmpty) {
        session.execute(
          core.AddStrokes(
            pageId: pageId,
            strokes: [for (final s in strokes) s.copyWith(pageId: pageId)],
          ),
        );
      }
      if (objects.isNotEmpty) {
        session.execute(
          core.AddObjects(
            pageId: pageId,
            objects: [
              for (final o in objects)
                o.pageId == pageId
                    ? o
                    : o.copyTo(
                        id: o.id,
                        pageId: pageId,
                        createdAt: o.createdAt,
                      ),
            ],
          ),
        );
      }
      session.closePage(pageId);
    }
    session.clearHistory();
    await session.flush();
  } finally {
    await session.close();
  }
  return note.id;
}

class EditorTestHandles {
  EditorTestHandles._(
    this._tester,
    this._recorderOf, {
    required this.store,
    required this.noteId,
    required this.seedKey,
    required this.driver,
    this.audioRecorder,
    this.audioPlayback,
    this.imageImporter,
    this.stylusExtras,
  });

  final core.NoteStore store;

  /// (v2) With fakeAudio: CORE's fake audio ports (overridden providers).
  final FakeAudioRecorder? audioRecorder;
  final FakeAudioPlayback? audioPlayback;

  /// (v2) The image slot fake, when pumpEditor got one.
  final FakeImageImporter? imageImporter;

  /// (v2) The Pencil source fake, when pumpEditor got one.
  final FakeStylusExtras? stylusExtras;
  final String noteId;

  /// Prefix of the seeded page ids ([seededPageId]).
  final String seedKey;
  final PointerDriver driver;
  final WidgetTester _tester;
  final RecordingNoteSession? Function() _recorderOf;

  /// How often EditorScreen.onClose ran.
  int closeCount = 0;

  /// The id of page [index] of the seeded note.
  core.PageId pageId(int index) => seededPageId(seedKey, index);

  /// The editor's provider container: the innermost ProviderScope at or under
  /// EditorScreen, else the root scope.
  ProviderContainer get container {
    final screen = find.byType(EditorScreen);
    // Every ProviderScope builds an UncontrolledProviderScope that carries
    // its container; the last one under EditorScreen is the innermost.
    final scopes = find.descendant(
      of: screen,
      matching: find.byType(UncontrolledProviderScope),
    );
    if (scopes.evaluate().isNotEmpty) {
      return _tester.widget<UncontrolledProviderScope>(scopes.last).container;
    }
    return ProviderScope.containerOf(_tester.element(screen), listen: false);
  }

  /// The real (fake-store) session; throws while the note is still opening.
  core.NoteSession get session {
    final rec = recorder;
    if (rec != null) return rec.inner;
    final open = container.read(core.noteSessionProvider(noteId)).value;
    return open ?? (throw StateError('the note session is not open yet'));
  }

  /// The recording wrapper (null with recordSession: false or before open).
  RecordingNoteSession? get recorder => _recorderOf();

  /// The note's ViewportController (editorViewportProvider).
  ViewportController get viewport => container.read(editorViewportProvider);

  /// The registry of mounted pages (editorMountedPagesProvider).
  MountedPages get mountedPages => container.read(editorMountedPagesProvider);

  /// The INK controller of page [pageIndex] (by the session's current page
  /// order); mounted pages only (StateError otherwise).
  ink.InkPageController controllerOf(int pageIndex) {
    final id = session.pages[pageIndex].id;
    final mount = mountedPages[id];
    if (mount == null) {
      throw StateError('page $pageIndex ($id) is not mounted');
    }
    return mount.controller;
  }

  /// Top-left of the page area (PageViewport) in global coordinates — the
  /// origin of the viewport's screen coordinates.
  Offset get viewportOrigin => _tester.getTopLeft(find.byType(PageViewport));

  /// Global position of page point [pagePt] (pt) on page [pageIndex].
  Offset toGlobal(int pageIndex, Offset pagePt) =>
      viewportOrigin + viewport.pageToScreen(pageIndex, pagePt);

  /// Page point (pt) on page [pageIndex] under the global position [global].
  Offset toPage(int pageIndex, Offset global) =>
      viewport.screenToPage(pageIndex, global - viewportOrigin);

  /// Global position of viewport point [screen] (viewport coordinates).
  Offset viewportToGlobal(Offset screen) => viewportOrigin + screen;

  /// Pumps frames (no fake time) until the viewport has its size and every
  /// mounted page is loaded; at most [maxFrames].
  Future<void> settlePages({int maxFrames = 10}) async {
    for (var i = 0; i < maxFrames; i++) {
      final open = container.read(editorSessionProvider).hasValue;
      if (open) {
        final v = viewport;
        final mounted = mountedPages.all.toList();
        final range = v.mountedRange;
        final expected = range == null ? -1 : range.last - range.first + 1;
        if (!v.viewportSize.isEmpty &&
            mounted.length == expected &&
            mounted.every((m) => m.isLoaded.value) &&
            !_tester.binding.hasScheduledFrame) {
          return;
        }
      }
      await _tester.pump();
    }
  }
}

/// (v2.14-ui) A tap on the toolbar with no side effect — outside the editor's
/// tap groups: the blank end of the title slot (the title itself opens
/// 노트 정보 now).
Future<void> tapToolbarBlank(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(EditorToolbar.titleSlotKey));
  await tester.tapAt(Offset(rect.right - 8, rect.center.dy));
}
