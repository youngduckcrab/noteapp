// lib/src/commands/editor_commands.dart — 04-editor 6.8, 5.1.3.
//
// E-08: the three CORE entry points (_run, _runAsync, _runHistory), the ink
// hand-off (commitInkEdit), undo / redo and the user messages. E-09: clearing
// the current page. E-10: copy / paste / delete of the selection, clearing it
// and selecting a tool. E-12: zoom, screen scrolling, the developer overlay
// toggle and Esc for the keyboard shortcuts. E-13: flushAll (leaving), the
// menu context and navigateToPage, the finger-drawing toggle, the page flip
// mode, adding a page at the end. E-14: the eyedropper and notices. E-17: the
// page commands (add, delete, duplicate, move), the page panel and its
// selection mode (Esc, Delete, the menu context's selectedPageIds).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/dev_tools.dart' as ink_dev;
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../di/editor_extensions.dart';
import '../di/stylus_extras.dart';
import '../document/mounted_pages.dart';
import '../input/input_router.dart';
import '../objects/object_factory.dart';
import '../objects/object_placement.dart';
import '../scope/editor_scope.dart';
import '../state/color_palette.dart';
import '../state/page_panel.dart';
import '../state/popup.dart';
import '../state/preset_bar.dart';
import '../state/settings/editor_settings.dart';
import '../state/settings/editor_settings_notifier.dart';
import '../state/settings/pre_roll.dart';
import '../stylus/stylus_extras_listener.dart' show penOnlyEffectiveWith;
import '../tools/element_clipboard.dart';
import '../tools/interaction_host.dart';
import '../tools/selection.dart';
import '../tools/tool_controller.dart';
import '../tools/tool_options.dart';
import '../tools/tool_state.dart';
import '../ui/dev/dev_metrics.dart';
import '../ui/editor_strings.dart';
import '../ui/pages/page_choices.dart';
import '../viewport/viewport_controller.dart';
import '../viewport/viewport_memory.dart';
import 'extension_runner.dart';

/// Single place for actions shared by toolbar, gestures, shortcuts, menus — and the
/// only place that runs CORE commands (5.1.3). Per note (scoped).
class EditorCommands {
  EditorCommands(
    this._ref, {
    required this._session,
    required this._viewport,
    required this._pages,
  });

  final Ref _ref;
  final core.NoteSession _session;
  final ViewportController _viewport;
  final MountedPages _pages;
  final StreamController<String> _messages = StreamController.broadcast();
  final StreamController<int> _pagesDeleted = StreamController.broadcast();
  InputRouter? _router;
  InteractionHost? _host;
  bool _disposed = false;

  /// Short notices for the user (snackbar text): a command refused on a
  /// read-only note, a command that failed.
  Stream<String> get messages => _messages.stream;

  /// How many pages each successful deletePages removed: the snack bar
  /// "페이지를 삭제했어요 [되돌리기]" (6.11.1).
  Stream<int> get pagesDeleted => _pagesDeleted.stream;

  /// The mounted pages this note's commands may touch (contract E-2).
  MountedPages get pages => _pages;

  /// Called by editorInputRouterProvider: undo / redo are ignored while the
  /// router drives a tool interaction.
  void bindRouter(InputRouter router) => _router = router;

  /// Called by editorInteractionHostProvider: Esc closes the host's context
  /// menu (the host depends on these commands, so it is bound afterwards).
  void bindHost(InteractionHost host) => _host = host;

  /// (v2, E2-05) true while the router drives a tool interaction — the
  /// action runner (6.4.3) ignores everything but the palettes then.
  bool get interactionActive => _router?.hasActiveInteraction ?? false;

  /// (v2, E2-05) EditorAction.contextMenu at [viewport] (the 1st-round long
  /// press menu: on the selection its menu, elsewhere the context menu).
  void openContextMenuAt(Offset viewport) {
    if (!_disposed) _host?.openContextMenuAt(viewport);
  }

  // ---- commands (5.1.3) ----

  /// One gesture = one InkEdit = one execute (contract E-1, 7.2.15 hand-off).
  /// Commit failure (contract 7.2.15 v1.1, C11-16): when execute throws (ReadOnlyNoteException
  /// etc.), _run calls onRejected → controller.discardEdit(edit), which drops the pending
  /// display of every id of the edit (added, removedIds, targetIds) — erased / split /
  /// moved strokes show their committed state again at once. Returns true when committed.
  bool commitInkEdit(ink.InkPageController controller, ink.InkEdit edit) {
    if (edit.isEmpty) return false; // nothing pending (INK 4.6)
    final committed =
        _run(
          edit.toCommand(),
          onRejected: () => controller.discardEdit(edit),
        ) !=
        null;
    if (committed &&
        edit.kind == ink.InkEditKind.addStroke &&
        edit.added.length == 1) {
      final metrics = _ref.read(editorDevMetricsProvider);
      if (metrics.isRunning) {
        metrics.recordStrokeCommitted(
          pointCount: edit.added.single.points.length,
          recordingOffsetMs: edit.added.single.recordingOffsetMs,
        );
      }
    }
    return committed;
  }

  /// After the confirmation dialog (6.6.4 #5, E-09):
  /// core.ClearPage(pageId: current page, filter: eraser filter,
  /// includeObjects: [includeObjects] — v2.1, m5-7/04-editor 6.17) through
  /// _runAsync: one step. Ignored on a read-only note.
  Future<void> clearCurrentPage({bool includeObjects = false}) async {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final pages = _session.pages;
    if (pages.isEmpty) return;
    final index = _viewport.currentPageIndex.value.clamp(0, pages.length - 1);
    await _runAsync(
      core.ClearPage(
        pageId: pages[index].id,
        filter: _ref.read(editorToolProvider).eraser.filter,
        includeObjects: includeObjects,
      ),
    );
  }

  /// Copies the selected elements — (v2, m5-7/04-editor 6.7.3) strokes AND
  /// objects, read from CORE state (session.pageIfLoaded(pageId).elementById)
  /// — to the app clipboard (6.8). Not a command; allowed on a read-only
  /// note.
  void copySelection() {
    if (_disposed) return;
    final selection = _ref.read(editorSelectionProvider);
    if (selection == null) return;
    final page = _session.pageIfLoaded(selection.pageId);
    if (page == null) return;
    final elements = [
      for (final id in selection.elementIds) ?page.elementById(id),
    ];
    if (elements.isEmpty) return;
    _ref.read(editorClipboardProvider.notifier).copy(elements);
  }

  /// (v2, 6.7.3) Cut = copy, then commitInkEdit(controller, sel.delete())
  /// (one step — RemoveStrokes, or RemoveElements with objects). A rejected
  /// delete keeps the clipboard (the copy happened — accepted) and the
  /// selection. Ignored on a read-only note.
  void cutSelection() {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    if (inkSelectionOf(_pages, _ref.read(editorSelectionProvider)) == null) {
      return;
    }
    copySelection();
    deleteSelection();
  }

  /// (v2, 6.7.3) Duplicate = commitInkEdit(controller, sel.duplicate()) (one
  /// step — AddStrokes, AddObjects or their composite; copies +16 pt, new
  /// ids, on top); accepted → the new elements (edit.added +
  /// edit.addedObjects) selected with origin paste (6.6.3), the tool kept.
  /// Ignored on a read-only note, when the page would pass the object limit
  /// (notice — 6.21) and during a drag.
  void duplicateSelection() {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final selection = _ref.read(editorSelectionProvider);
    final sel = inkSelectionOf(_pages, selection);
    if (selection == null || sel == null || selection.isDragging) return;
    final page = _session.pageIfLoaded(selection.pageId);
    if (page != null &&
        ObjectFactory.exceedsLimit(page, sel.objectIds.length)) {
      _message(
        EditorStrings.objectLimitReached(
          core.PageObjectLimits.maxObjectsPerPage,
        ),
      );
      return;
    }
    final controller = _pages[selection.pageId]!.controller;
    final edit = sel.duplicate();
    if (commitInkEdit(controller, edit)) {
      _ref.read(editorSelectionProvider.notifier).select(selection.pageId, {
        for (final s in edit.added) s.id,
        for (final o in edit.addedObjects) o.id,
      }, origin: SelectionOrigin.paste);
    }
  }

  /// Pastes the clipboard (6.6.7): at [screenPoint] when it is on a page,
  /// else centred on the screen centre in the current page's coordinates
  /// (repeated pastes move +16 pt each). (v2, m5-7/04-editor 6.8) strokes and
  /// objects: one step through _runAsync — core.AddStrokes or core.AddObjects
  /// when only one kind is there, else CompositeCommand([AddStrokes,
  /// AddObjects]); over the page's object limit (5.1.1) → the notice, no
  /// command. Then the pasted elements selected (controller.select —
  /// contract 7.2.15 paste rule); (v2, 6.6.3 — Q8) the tool stays and the
  /// selection's origin is paste, so a body drag moves it with any tool.
  /// Ignored on a read-only note.
  Future<void> paste({Offset? screenPoint}) async {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final clipboard = _ref.read(editorClipboardProvider.notifier);
    final content = _ref.read(editorClipboardProvider);
    if (content == null) return;
    final pages = _session.pages;
    if (pages.isEmpty || _viewport.viewportSize.isEmpty) return;
    final hit = screenPoint == null ? null : _viewport.hitPage(screenPoint);
    final int index;
    final Offset center;
    if (hit != null) {
      index = hit.index;
      center = _viewport.screenToPage(index, screenPoint!);
    } else {
      index = _viewport.currentPageIndex.value.clamp(0, pages.length - 1);
      center = _viewport.screenToPage(
        index,
        _viewport.viewportSize.center(Offset.zero),
      );
    }
    final page = pages[index];
    final loaded = _session.pageIfLoaded(page.id);
    if (loaded != null &&
        ObjectFactory.exceedsLimit(loaded, content.objectCount)) {
      _message(
        EditorStrings.objectLimitReached(
          core.PageObjectLimits.maxObjectsPerPage,
        ),
      );
      return;
    }
    final pasted = clipboard.instantiate(
      pageId: page.id,
      pageSize: Size(page.size.width, page.size.height),
      center: center,
      explicitPoint: hit != null,
      newId: _ref.read(core.idGeneratorProvider).newId,
      createdAt: _ref.read(core.clockProvider).now().millisecondsSinceEpoch,
    );
    final strokes = pasted.strokes, objects = pasted.objects;
    if (strokes.isEmpty && objects.isEmpty) return;
    final addStrokes = core.AddStrokes(pageId: page.id, strokes: strokes);
    final addObjects = core.AddObjects(pageId: page.id, objects: objects);
    final receipt = await _runAsync(
      objects.isEmpty
          ? addStrokes
          : strokes.isEmpty
          ? addObjects
          : core.CompositeCommand([addStrokes, addObjects]),
    );
    if (_disposed || receipt == null) return;
    _ref.read(editorSelectionProvider.notifier).select(page.id, {
      for (final s in strokes) s.id,
      for (final o in objects) o.id,
    }, origin: SelectionOrigin.paste);
  }

  /// Deletes the selected strokes: commitInkEdit(controller, sel.delete())
  /// (one RemoveStrokes). A rejected commit shows them again (discardEdit) and
  /// keeps the selection. Ignored on a read-only note.
  void deleteSelection() {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final selection = _ref.read(editorSelectionProvider);
    final sel = inkSelectionOf(_pages, selection);
    if (selection == null || sel == null) return;
    final controller = _pages[selection.pageId]!.controller;
    if (commitInkEdit(controller, sel.delete())) {
      _ref.read(editorSelectionProvider.notifier).clear();
    }
  }

  void clearSelection() {
    if (_disposed) return;
    _ref.read(editorSelectionProvider.notifier).clear();
  }

  /// (v2, m5-7/04-editor 6.6.6 — selection menu '더보기 > 90° 돌리기', the
  /// V5 smoke's deterministic path) rotate(bounds, π/2) committed at once —
  /// the preview transform is set and committed in the same call, so no
  /// frame shows it: one TransformElements through commitInkEdit, then the
  /// same ids selected again (origin kept — 6.6.3). A rejected commit has
  /// called discardEdit (old place, selection stays). Nothing for unknown
  /// objects only, during a drag or on a read-only note.
  void rotateSelection90() {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final selection = _ref.read(editorSelectionProvider);
    final sel = inkSelectionOf(_pages, selection);
    if (selection == null || sel == null || selection.isDragging) return;
    final controller = _pages[selection.pageId]!.controller;
    final ids = sel.allIds.toSet();
    sel.setPreviewTransform(
      ink.SelectionGeometry.rotate(bounds: sel.bounds, radians: math.pi / 2),
    );
    final edit = sel.commitTransform();
    if (edit == null) {
      sel.setPreviewTransform(core.Affine2.identity);
      return;
    }
    if (commitInkEdit(controller, edit)) {
      _ref
          .read(editorSelectionProvider.notifier)
          .select(selection.pageId, ids, origin: selection.origin);
    }
  }

  /// (v2, m5-7/04-editor 6.7.2 — the recolor popup) commitInkEdit(controller,
  /// sel.recolor(argb)): one step — RestyleStrokes for strokes, UpdateObjects
  /// for shapes / text / math, their CompositeCommand when both are there.
  /// Accepted → [argb] goes to the front of the recent colours and the
  /// selection stays; rejected → INK's pending display dropped (discardEdit
  /// inside commitInkEdit), the selection stays. Nothing recolorable (images
  /// / unknown objects only — INK's edit isEmpty, S-14) → no command.
  /// Ignored on a read-only note and during a drag. Returns whether it
  /// committed.
  bool recolorSelection(int argb) {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return false;
    final selection = _ref.read(editorSelectionProvider);
    final sel = inkSelectionOf(_pages, selection);
    if (selection == null || sel == null || selection.isDragging) return false;
    final controller = _pages[selection.pageId]!.controller;
    final edit = sel.recolor(argb);
    if (!commitInkEdit(controller, edit)) return false;
    _ref.read(editorColorPaletteProvider.notifier).pushRecent(argb);
    return true;
  }

  /// (v2, E2-08 — m5-7/04-editor 6.6.5) The end of an edge / vertex / text
  /// width drag (and later the style / format edits — 6.7.5): ONE
  /// core.UpdateObjects([objects]) on [pageId] through [_run]. Rejected (a
  /// read-only race → the 1st-round notice, anything else → _rejected's
  /// report + '실행하지 못했어요') → false; the caller drops its preview.
  bool updateObjects(String pageId, List<core.PageObject> objects) {
    if (_disposed || objects.isEmpty) return false;
    return _run(core.UpdateObjects(pageId: pageId, objects: objects)) != null;
  }

  /// (v2, E2-09 — m5-7/04-editor 6.9.2) A drawn shape: ONE
  /// core.AddObjects([objects]) on the loaded page [pageId] through [_run];
  /// over the page's object limit (5.1.1) → the notice, no command. Returns
  /// whether it was accepted.
  bool addObjects(String pageId, List<core.PageObject> objects) {
    if (_disposed || objects.isEmpty) return false;
    final content = _session.pageIfLoaded(pageId);
    if (content != null &&
        ObjectFactory.exceedsLimit(content, objects.length)) {
      _message(
        EditorStrings.objectLimitReached(
          core.PageObjectLimits.maxObjectsPerPage,
        ),
      );
      return false;
    }
    return _run(core.AddObjects(pageId: pageId, objects: objects)) != null;
  }

  // ---- extension slots (m5-7/04-editor 6.7.4) ----

  /// (v2) `execute` of the extension contexts (EditorSelectionContext /
  /// EditorInsertContext): ONE command on the session, thrown errors passed
  /// on like NoteSession.execute (contract 7.2.10 — the item shows the
  /// message). A ReadOnlyNoteException first refreshes
  /// editorReadOnlyProvider (the side effect of [_rejected]).
  void executeForExtension(core.EditCommand command) {
    try {
      _session.execute(command);
    } on core.ReadOnlyNoteException {
      if (!_disposed) _ref.read(editorReadOnlyProvider.notifier).refresh();
      rethrow;
    }
  }

  /// (v2, 6.7.4) The EditorSelectionContext of the current selection — made
  /// at the press (a value copy) — or null (no selection, page not loaded).
  EditorSelectionContext? selectionContext() {
    if (_disposed) return null;
    final selection = _ref.read(editorSelectionProvider);
    return selectionContextFor(
      session: _session,
      selection: selection,
      sel: inkSelectionOf(_pages, selection),
      execute: executeForExtension,
      clearSelection: clearSelection,
    );
  }

  /// (v2, E2-12 — m5-7/04-editor 6.13.2) The EditorInsertContext of an
  /// insert menu item — made at the press: the current page, its visible
  /// part (ObjectPlacement.visibleRectPt), [executeForExtension] and
  /// selectObject (the object selected with origin insert — 6.6.3; ignored
  /// when the page holds no such object). Null before the note has pages.
  EditorInsertContext? insertContext() {
    if (_disposed) return null;
    final pages = _session.pages;
    if (pages.isEmpty) return null;
    final index = _viewport.currentPageIndex.value.clamp(0, pages.length - 1);
    final page = pages[index];
    return EditorInsertContext(
      noteId: _session.noteId,
      pageId: page.id,
      pageSize: page.size,
      visibleRectPt: ObjectPlacement.visibleRectPt(_viewport, index),
      execute: executeForExtension,
      selectObject: (id) {
        if (_disposed) return;
        if (_session.pageIfLoaded(page.id)?.objectById(id) == null) return;
        _ref.read(editorSelectionProvider.notifier).select(page.id, {
          id,
        }, origin: SelectionOrigin.insert);
      },
    );
  }

  // ---- images (m5-7/04-editor 6.12) ----

  /// (v2, E2-12 — 6.12.2 steps 3–4) An image the image slot returned, as a
  /// new ImageObject: on the page under [screenPoint] centred there (the
  /// long-press point of an image paste) when given and on a page, else on
  /// the current page centred on its visible part; sized and kept on the
  /// page by ObjectPlacement.forImage. Over the page's object limit (5.1.1)
  /// → the notice, no command; else ONE core.AddObjects through _runAsync
  /// (a note that turned read-only while the picker was open is refused
  /// there — the 1st-round notice), then the image selected with [origin]
  /// (insert from the insert menu, paste from an image paste — 6.6.3), the
  /// tool kept. Returns whether it was added.
  Future<bool> insertImage(
    core.ImportedImage imported, {
    Offset? screenPoint,
    required SelectionOrigin origin,
  }) async {
    if (_disposed) return false;
    final pages = _session.pages;
    if (pages.isEmpty) return false;
    final hit = screenPoint == null || _viewport.viewportSize.isEmpty
        ? null
        : _viewport.hitPage(screenPoint);
    final index =
        hit?.index ??
        _viewport.currentPageIndex.value.clamp(0, pages.length - 1);
    final page = pages[index];
    final rect = ObjectPlacement.forImage(
      pageSize: page.size,
      visibleRectPt: ObjectPlacement.visibleRectPt(_viewport, index),
      pixelWidth: imported.pixelWidth,
      pixelHeight: imported.pixelHeight,
      center: hit == null ? null : _viewport.screenToPage(index, screenPoint!),
    );
    final loaded = _session.pageIfLoaded(page.id);
    if (loaded != null && ObjectFactory.exceedsLimit(loaded, 1)) {
      _message(
        EditorStrings.objectLimitReached(
          core.PageObjectLimits.maxObjectsPerPage,
        ),
      );
      return false;
    }
    final image = ObjectFactory.image(
      pageId: page.id,
      rectPt: rect,
      imported: imported,
      newId: _ref.read(core.idGeneratorProvider).newId,
      createdAt: _ref.read(core.clockProvider).now().millisecondsSinceEpoch,
    );
    final receipt = await _runAsync(
      core.AddObjects(pageId: page.id, objects: [image]),
    );
    if (_disposed || receipt == null) return false;
    _ref.read(editorSelectionProvider.notifier).select(page.id, {
      image.id,
    }, origin: origin);
    return true;
  }

  /// (v2, E2-12 — 6.12.3) An image page: [base]'s size turned to the
  /// image's orientation (ObjectPlacement.imagePageSize), background
  /// core.ImageBackground(fit: contain) on [base]'s paper colour, inserted
  /// at [placement] relative to [base] (remembered when the source was
  /// pressed; the current page when [base] is gone by now) as ONE
  /// core.InsertPages through _runAsync (a read-only race → the 1st-round
  /// notice), then the viewport goes to the new page.
  Future<void> insertImagePage(
    core.ImportedImage imported, {
    required core.Page base,
    required AddPagePlacement placement,
  }) async {
    if (_disposed) return;
    final pages = _session.pages;
    if (pages.isEmpty) return;
    final current =
        pages[_viewport.currentPageIndex.value.clamp(0, pages.length - 1)];
    final anchorId = pages.any((p) => p.id == base.id) ? base.id : current.id;
    final request = AddPageRequest(
      placement: placement,
      size: ObjectPlacement.imagePageSize(
        base.size,
        imported.pixelWidth,
        imported.pixelHeight,
      ),
      background: core.ImageBackground(
        assetId: imported.asset.id,
        fit: core.ImageFit.contain,
        paperColorArgb: base.background.paperColorArgb,
      ),
      anchorPageId: placement == AddPagePlacement.end ? null : anchorId,
    );
    final receipt = await _runAsync(
      core.InsertPages(
        drafts: [
          core.PageDraft(size: request.size, background: request.background),
        ],
        position: request.positionFor(current.id),
      ),
    );
    if (_disposed || receipt == null) return;
    _jumpToInserted(receipt);
  }

  // ---- pages (6.11, 5.1.3 — each one undo step) ----

  /// Add-page sheet [추가] (6.11.4): core.InsertPages(one draft, at
  /// request.positionFor(current page)) through _runAsync, then the viewport
  /// goes to the inserted page. Ignored on a read-only note.
  Future<void> addPage(AddPageRequest request) async {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final pages = _session.pages;
    if (pages.isEmpty) return;
    final current =
        pages[_viewport.currentPageIndex.value.clamp(0, pages.length - 1)];
    final receipt = await _runAsync(
      core.InsertPages(
        drafts: [
          core.PageDraft(size: request.size, background: request.background),
        ],
        position: request.positionFor(current.id),
      ),
    );
    if (_disposed || receipt == null) return;
    _jumpToInserted(receipt);
  }

  /// core.DeletePages through _run (6.11.1, EDITOR-3-1). Ignored when nothing
  /// would remain (the buttons are disabled then — contract 7.2.6), for ids
  /// not in the note and on a read-only note. A deletion → [pagesDeleted]
  /// (snack bar with "되돌리기").
  void deletePages(List<String> pageIds) {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final pages = _session.pages;
    final wanted = pageIds.toSet();
    final ids = [
      for (final p in pages)
        if (wanted.contains(p.id)) p.id,
    ];
    if (ids.isEmpty || ids.length >= pages.length) return;
    final receipt = _run(core.DeletePages(pageIds: ids));
    if (receipt != null && !_disposed) _pagesDeleted.add(ids.length);
  }

  /// core.DuplicatePages through _runAsync (each copy right after its
  /// source); one page → the viewport goes to the copy. Ignored on a
  /// read-only note.
  Future<void> duplicatePages(List<String> pageIds) async {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final wanted = pageIds.toSet();
    final ids = [
      for (final p in _session.pages)
        if (wanted.contains(p.id)) p.id,
    ];
    if (ids.isEmpty) return;
    final receipt = await _runAsync(core.DuplicatePages(pageIds: ids));
    if (_disposed || receipt == null || ids.length != 1) return;
    _jumpToInserted(receipt);
  }

  /// Page panel drag (6.11.1): [toIndex] is onReorderItem's final index.
  /// core.MovePages(position: toIndex == 0 ? PageAtStart : PageAfter(rest[toIndex − 1]))
  /// through _run (5.1.3); no command when the page stays where it is. The
  /// viewport keeps the page it shows (6.3.4 anchor). Ignored on a read-only
  /// note.
  void movePage(String pageId, int toIndex) {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final ids = [for (final p in _session.pages) p.id];
    final from = ids.indexOf(pageId);
    if (from < 0) return;
    final rest = [...ids]..removeAt(from);
    final to = toIndex.clamp(0, rest.length);
    if (to == from) return;
    _run(
      core.MovePages(
        pageIds: [pageId],
        position: to == 0
            ? const core.PageAtStart()
            : core.PageAfter(rest[to - 1]),
      ),
    );
  }

  void _jumpToInserted(core.CommandReceipt receipt) {
    final inserted = receipt.edit.insertedPageIds;
    if (inserted.isEmpty) return;
    final index = _session.pages.indexWhere((p) => p.id == inserted.first);
    if (index >= 0) unawaited(_viewport.jumpToPage(index));
  }

  /// Developer menu (6.12.4): [count] synthetic strokes on the current page
  /// (ink.InkDevTools.syntheticStrokes, ids from core.idGeneratorProvider) as
  /// one core.AddStrokes through _runAsync — one undo step. Ignored on a
  /// read-only note.
  Future<void> addSyntheticStrokes(int count) async {
    if (_disposed || _ref.read(editorReadOnlyProvider) || count <= 0) return;
    final pages = _session.pages;
    if (pages.isEmpty) return;
    final current =
        pages[_viewport.currentPageIndex.value.clamp(0, pages.length - 1)];
    final strokes = ink_dev.InkDevTools.syntheticStrokes(
      pageId: current.id,
      pageSize: current.size,
      count: count,
      newId: _ref.read(core.idGeneratorProvider).newId,
      createdAt: _ref.read(core.clockProvider).now().millisecondsSinceEpoch,
    );
    await _runAsync(core.AddStrokes(pageId: current.id, strokes: strokes));
  }

  /// Toolbar [▤]: opens / closes the page panel (closing leaves the
  /// selection mode).
  void togglePagePanel() {
    if (_disposed) return;
    _ref.read(editorPagePanelProvider.notifier).toggleOpen();
  }

  /// Delete / Backspace (6.8): the selected strokes; with no stroke selection
  /// in the page selection mode, the selected pages (ignored when nothing
  /// would remain).
  void deleteSelectionOrPages() {
    if (_disposed) return;
    if (_ref.read(editorSelectionProvider) != null) {
      deleteSelection();
      return;
    }
    final panel = _ref.read(editorPagePanelProvider);
    if (!panel.isSelecting || panel.selectedIds.isEmpty) return;
    deletePages(panel.orderedSelection([for (final p in _session.pages) p.id]));
  }

  void selectTool(EditorTool tool) {
    if (_disposed) return;
    _ref.read(editorToolProvider.notifier).selectTool(tool);
  }

  // ---- navigation / UI (6.8) ----

  /// ×1.25 about the screen centre (ViewportController.zoomStep).
  void zoomIn() {
    if (!_disposed) unawaited(_viewport.zoomStep(zoomIn: true));
  }

  /// ÷1.25 about the screen centre.
  void zoomOut() {
    if (!_disposed) unawaited(_viewport.zoomStep(zoomIn: false));
  }

  /// Zoom 1 = fit width (paged mode: the current page centred).
  void zoomToFit() {
    if (!_disposed) unawaited(_viewport.zoomToFit());
  }

  /// ±0.9 viewport along the main axis; the next / previous page in paged
  /// mode. [direction] > 0 = forward.
  void scrollByViewport(int direction) {
    if (!_disposed) unawaited(_viewport.scrollByViewport(direction));
  }

  /// Flips EditorSettings.showDevOverlay (device setting). The overlay is
  /// shown when this or the URL flag is on (editorDevOverlayVisibleProvider,
  /// 6.12).
  void toggleDevOverlay() {
    if (_disposed) return;
    _ref.read(editorSettingsProvider.notifier).toggleDevOverlay();
  }

  /// Pen panel [스포이드] (6.6.8): closes the popup (and the context menu)
  /// and turns the eyedropper on — the banner shows and the next down on the
  /// canvas picks a stroke's colour. Allowed on a read-only note.
  void startEyedropper() {
    if (_disposed) return;
    _ref.read(editorPopupProvider.notifier).close();
    _host?.closeContextMenu();
    _ref.read(editorToolProvider.notifier).setEyedropper(true);
  }

  /// A short notice for the user (snack bar — the eyedropper's result).
  void notify(String message) => _message(message);

  /// Esc: close popup → cancel eyedropper → leave page selection mode → clear selection
  /// (first that applies). The open context menu counts as a popup (E-10).
  void escape() {
    if (_disposed) return;
    if (_ref.read(editorPopupProvider) != null) {
      _ref.read(editorPopupProvider.notifier).close();
      return;
    }
    final host = _host;
    if (host != null && host.contextMenu.value != null) {
      host.closeContextMenu();
      return;
    }
    if (_ref.read(editorToolProvider).eyedropperActive) {
      _ref.read(editorToolProvider.notifier).setEyedropper(false);
      return;
    }
    if (_ref.read(editorPagePanelProvider).isSelecting) {
      _ref.read(editorPagePanelProvider.notifier).setSelecting(false);
      return;
    }
    _ref.read(editorSelectionProvider.notifier).clear();
  }

  /// Finger drawing on ↔ off: on = InputMode.fingerDrawing, off =
  /// InputMode.penOnly (6.9.1 [✋]). From auto it goes to the opposite of
  /// what auto does now (EditorSettings.isPenOnlyEffective — (v2, E2-18)
  /// with iPadOS '펜슬로만 그리기', 6.5.3).
  void toggleFingerDrawing() {
    if (_disposed) return;
    final settings = _ref.read(editorSettingsProvider);
    final penOnly = penOnlyEffectiveWith(
      settings,
      _ref.read(stylusExtrasProvider).capabilities,
    );
    _ref
        .read(editorSettingsProvider.notifier)
        .setInputMode(penOnly ? InputMode.fingerDrawing : InputMode.penOnly);
  }

  /// More menu '페이지 넘김' (vertical scroll / horizontal paging). The
  /// viewport follows the setting (editorViewportProvider).
  void setPageFlipMode(PageFlipMode mode) {
    if (_disposed) return;
    _ref.read(editorSettingsProvider.notifier).setPageFlipMode(mode);
  }

  /// 04-editor 4.5 table: built when the more menu opens and when the
  /// add-page sheet's '다른 소스' row is pressed (6.11.5). selectedPageIds =
  /// the page panel selection in note order while the selection mode is on,
  /// else const [].
  EditorMenuContext menuContext() {
    final ids = [for (final p in _session.pages) p.id];
    final panel = _ref.read(editorPagePanelProvider);
    return EditorMenuContext(
      noteId: _session.noteId,
      pageIds: ids,
      currentPageIndex: _viewport.currentPageIndex.value,
      selectedPageIds: panel.isSelecting
          ? panel.orderedSelection(ids)
          : const [],
      navigateToPage: navigateToPage,
    );
  }

  /// 6.11.6: an unknown id (deleted page) is ignored; else the page is
  /// brought into view, and [focusRectPt] (displayed page pt, clipped to the
  /// page) is shown when given — (v2, m5-7/04-editor 6.16) and flashed
  /// (editorFocusFlashProvider; a rect off the page → no flash).
  void navigateToPage(String pageId, Rect? focusRectPt) {
    if (_disposed) return;
    final pages = _session.pages;
    final index = pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return;
    final rect = clipFocusRect(focusRectPt, pages[index].size);
    unawaited(_viewport.revealPageRect(index, focusRectPt: rect));
    if (rect != null) {
      _ref.read(editorFocusFlashProvider).show(pageId: pageId, rectPt: rect);
    }
  }

  /// A page like the last one (size, background — a PDF / image page gives
  /// a blank page of its paper colour) at the end, then the viewport goes to
  /// it (6.11.4 '+ 페이지'; also the '페이지가 없어요' state — blank A4 when
  /// there is no page). Ignored on a read-only note.
  Future<void> addPageAtEndLikeLast() async {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final pages = _session.pages;
    final draft = pages.isEmpty
        ? core.PageDraft.blankA4
        : core.PageDraft(
            size: pages.last.size,
            background: switch (pages.last.background) {
              final core.BlankBackground b => b,
              final core.TemplateBackground t => t,
              final other => core.BlankBackground(
                paperColorArgb: other.paperColorArgb,
              ),
            },
          );
    final receipt = await _runAsync(
      core.InsertPages(drafts: [draft], position: const core.PageAtEnd()),
    );
    if (_disposed || receipt == null) return;
    unawaited(_viewport.jumpToPage(_session.pages.length - 1));
  }

  /// session.flush() + settings / tool / colour / viewport debounced writers (6.17).
  /// The current position is saved first. Each failure is reported; the
  /// Future completes when every write has finished (no timeout — contract
  /// 7.2.9 v1.2).
  Future<void> flushAll() async {
    if (_disposed) return;
    final memory = _ref.read(editorViewportMemoryProvider);
    final anchor = _viewport.captureAnchor();
    if (anchor != null) memory.save(_session.noteId, anchor);
    Future<void> guarded(Future<void> Function() write, String what) async {
      try {
        await write();
      } on Object catch (error, stack) {
        _report(error, stack, 'while flushing $what');
      }
    }

    await Future.wait([
      guarded(_session.flush, 'the note session'),
      guarded(_ref.read(editorSettingsProvider.notifier).flush, 'settings'),
      guarded(_ref.read(editorToolProvider.notifier).flush, 'tool state'),
      guarded(_ref.read(editorColorPaletteProvider.notifier).flush, 'colours'),
      guarded(_ref.read(editorPresetBarProvider.notifier).flush, 'preset bar'),
      // (v2, E2-03)
      guarded(
        _ref.read(editorToolOptionsProvider.notifier).flush,
        'tool options',
      ),
      guarded(_ref.read(editorPreRollMsProvider.notifier).flush, 'pre-roll'),
      guarded(memory.flush, 'the last position'),
    ]);
  }

  /// Through _runHistory (5.1.3): ignored while an interaction is active or read-only;
  /// a racing ReadOnlyNoteException (N-4 v1.1) is caught there.
  Future<void> undo() => _history(_session.undo);
  Future<void> redo() => _history(_session.redo);

  Future<void> _history(Future<core.UndoRedoResult> Function() step) async {
    if (_disposed) return;
    if (_router?.hasActiveInteraction ?? false) return;
    if (_ref.read(editorReadOnlyProvider)) return;
    final result = await _runHistory(step);
    if (_disposed || result == null || !result.applied) return;
    final affected = result.affectedPageIds;
    if (affected.isEmpty) return;
    // The first affected page in note order; scrolled to when off screen.
    final index = _session.pages.indexWhere((p) => affected.contains(p.id));
    if (index >= 0) await _viewport.ensurePageVisible(index);
  }

  // ---- CORE entry points: the only callers of session.execute /
  // executeAsync / undo / redo (EDITOR-3-1) ----

  /// Runs one CORE command for one user action, synchronously (N-1). Never called from a
  /// session stream listener (N-2 v1.1: that would throw StateError). Returns null when the
  /// command was rejected; [onRejected] then runs exactly once before returning — gesture
  /// commits pass () => controller.discardEdit(edit) (contract 7.2.15 v1.1 'commit failure').
  core.CommandReceipt? _run(
    core.EditCommand command, {
    VoidCallback? onRejected,
  }) {
    try {
      return _session.execute(command);
    } on Object catch (error, stack) {
      _rejected(error, stack, onRejected, 'while running ${command.label}');
      return null;
    }
  }

  /// Same for commands that may need pages loaded first (N-3). Applied after the first
  /// await (N-2 v1.1).
  Future<core.CommandReceipt?> _runAsync(
    core.EditCommand command, {
    VoidCallback? onRejected,
  }) async {
    try {
      return await _session.executeAsync(command);
    } on Object catch (error, stack) {
      _rejected(error, stack, onRejected, 'while running ${command.label}');
      return null;
    }
  }

  /// session.undo / session.redo (applied after the first await, N-2 v1.1). Read-only notes
  /// throw ReadOnlyNoteException here too (N-4 v1.1). null when rejected.
  Future<core.UndoRedoResult?> _runHistory(
    Future<core.UndoRedoResult> Function() step,
  ) async {
    try {
      return await step();
    } on Object catch (error, stack) {
      _rejected(error, stack, null, 'while undoing or redoing');
      return null;
    }
  }

  /// (v2, E2-01 — m5-7/04-editor 6.11.5) The one command of a text edit
  /// session, through [_run]. A read-only rejection (a race: the note turned
  /// read-only while editing) also copies [text] to the system clipboard —
  /// text only, the app clipboard is untouched — and the notice says so
  /// (review S-11). Returns null when rejected.
  core.CommandReceipt? runTextSession(
    core.EditCommand command, {
    required String text,
  }) {
    try {
      return _session.execute(command);
    } on core.ReadOnlyNoteException {
      if (!_disposed) _ref.read(editorReadOnlyProvider.notifier).refresh();
      unawaited(
        Clipboard.setData(ClipboardData(text: text)).catchError(
          (Object error, StackTrace stack) =>
              _report(error, stack, 'while copying the edited text'),
        ),
      );
      _message(
        '${EditorStrings.readOnlyToast}\n'
        '${EditorStrings.textCopiedToClipboard}',
      );
      return null;
    } on Object catch (error, stack) {
      _rejected(error, stack, null, 'while running ${command.label}');
      return null;
    }
  }

  /// [_run] for tests (editor_commands_test: the exception table of 5.1.3).
  @visibleForTesting
  core.CommandReceipt? debugRun(
    core.EditCommand command, {
    VoidCallback? onRejected,
  }) => _run(command, onRejected: onRejected);

  /// [_runAsync] for tests.
  @visibleForTesting
  Future<core.CommandReceipt?> debugRunAsync(
    core.EditCommand command, {
    VoidCallback? onRejected,
  }) => _runAsync(command, onRejected: onRejected);

  /// [_runHistory] for tests.
  @visibleForTesting
  Future<core.UndoRedoResult?> debugRunHistory(
    Future<core.UndoRedoResult> Function() step,
  ) => _runHistory(step);

  /// All three catch:
  ///   ReadOnlyNoteException     → read-only toast, editorReadOnlyProvider refreshed
  ///   PageNotOpenException      → reportError (bug: gesture on an unmounted page)
  ///   LastPageDeletionException → reportError (button should have been disabled)
  ///   SessionClosedException    → ignored (screen is closing)
  ///   StateError                → reportError (bug: re-entered from a listener, N-2 v1.1)
  ///   anything else             → reportError + snackbar "실행하지 못했어요" (ArgumentError etc.)
  /// On every rejection: onRejected?.call() once, then return null (never rethrow).
  void _rejected(
    Object error,
    StackTrace stack,
    VoidCallback? onRejected,
    String context,
  ) {
    if (onRejected != null) {
      try {
        onRejected();
      } on Object catch (e, s) {
        _report(e, s, 'while dropping a rejected edit');
      }
    }
    switch (error) {
      case core.ReadOnlyNoteException():
        _message(EditorStrings.readOnlyToast);
        if (!_disposed) _ref.read(editorReadOnlyProvider.notifier).refresh();
      case core.SessionClosedException():
        break;
      case core.PageNotOpenException() ||
          core.LastPageDeletionException() ||
          StateError():
        _report(error, stack, context);
      default:
        _report(error, stack, context);
        _message(EditorStrings.commandFailed);
    }
  }

  void _message(String text) {
    if (!_disposed) _messages.add(text);
  }

  void _report(Object error, StackTrace? stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription(context),
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _router = null;
    _host = null;
    unawaited(_messages.close());
    unawaited(_pagesDeleted.close());
  }
}
