// lib/src/ui/pages/page_panel_thumbnail.dart — 04-editor 6.11.3 (EDITOR-S7,
// contract 7.2.11 '페이지 패널 썸네일', 7.2.16 v1.1).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';

/// Page-panel thumbnail (renamed from the draft's PageThumbnail — core.PageThumbnail is
/// the CORE data type). Never pins the page (contract E-2): it reads, in this order,
///   1. session.pageIfLoaded(page.id) != null → ink.InkPageThumbnail(content:
///      InkPageContent.fromCore(...), width:, backgroundBuilders:, pencilGrain:) and
///      rebuilds 500 ms after the last pageChanges event of that page (listened only
///      while visible);
///   2. else core.pageThumbnailProvider(page.id) when its value isStaleFor(committed) is
///      false, committed = await core.noteContentReaderProvider.getPage(page.id)
///      → Image.memory(bytes, cacheWidth: width × dpr);
///   3. else noteContentReader.loadPage(page.id) once → ink.InkPageThumbnail (same args).
/// INK arguments (contract 7.2.16 v1.1, C11-19 — the INK widget reads no provider):
///   backgroundBuilders: ref.watch(ink.pageBackgroundBuildersProvider)  // read only, never
///                       overridden by EDITOR → PDF pages show their page (PDF builder)
///   pencilGrain:        ref.watch(ink.pencilGrainProvider)
/// Placeholder (paper colour) while loading. Does not write ThumbnailCache (optional,
/// not in this scope). RepaintBoundary.
///
/// The pageChanges subscription lives as long as this widget (the panel list
/// builds only the visible items). A page that gets loaded while shown (its
/// `load` event) moves to path 1 after the same 500 ms; a new
/// page.contentRevision while on path 2 / 3 checks the cache again.
class PagePanelThumbnail extends ConsumerStatefulWidget {
  const PagePanelThumbnail({super.key, required this.page, this.width = 120});
  final core.Page page;
  final double width;

  /// Rebuild delay after the last pageChanges event (path 1).
  static const Duration refreshDelay = Duration(milliseconds: 500);

  /// Thumbnails are at most this tall (6.11.1).
  static const double maxHeight = 200;

  /// Height for [width] and [size]: width × h / w, at most [maxHeight].
  static double heightFor(core.PageSize size, double width) =>
      math.min(width * size.height / size.width, maxHeight);

  static const placeholderKey = ValueKey('editor.pageThumbnail.placeholder');
  static const imageKey = ValueKey('editor.pageThumbnail.image');

  @override
  ConsumerState<PagePanelThumbnail> createState() => _PagePanelThumbnailState();
}

class _PagePanelThumbnailState extends ConsumerState<PagePanelThumbnail> {
  StreamSubscription<core.PageContentChange>? _changes;
  ProviderSubscription<AsyncValue<core.PageThumbnail?>>? _cacheSub;
  Timer? _refresh;

  /// Path 1: the session's content.
  core.PageContent? _live;

  /// Path 2: a cache entry checked against the committed page.
  core.PageThumbnail? _cached;

  /// Path 3: the committed content (loadPage).
  core.PageContent? _loaded;
  bool _loadStarted = false;

  /// Bumped on every reset: async results of an older generation are dropped.
  int _generation = 0;

  core.NoteSession get _session => ref.read(editorSessionValueProvider);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(PagePanelThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id) {
      _stop();
      _live = null;
      _start();
    } else if (_live == null &&
        oldWidget.page.contentRevision != widget.page.contentRevision) {
      _resetCommitted();
      final cache = _cacheSub;
      if (cache != null) _onCache(cache.read());
    }
  }

  void _start() {
    final id = widget.page.id;
    _live = _session.pageIfLoaded(id);
    _changes = _session.pageChanges(id).listen(_onChange);
    if (_live == null) _listenCache();
  }

  void _stop() {
    _refresh?.cancel();
    _refresh = null;
    unawaited(_changes?.cancel());
    _changes = null;
    _cacheSub?.close();
    _cacheSub = null;
    _resetCommitted();
  }

  void _resetCommitted() {
    _generation++;
    _cached = null;
    _loaded = null;
    _loadStarted = false;
  }

  void _onChange(core.PageContentChange change) {
    // The `load` event of content already shown changes nothing.
    final live = _live;
    if (live != null && identical(change.content, live)) return;
    _refresh?.cancel();
    _refresh = Timer(PagePanelThumbnail.refreshDelay, _refreshLive);
  }

  void _refreshLive() {
    _refresh = null;
    if (!mounted) return;
    final content = _session.pageIfLoaded(widget.page.id);
    if (content == null || identical(content, _live)) return;
    _cacheSub?.close();
    _cacheSub = null;
    _resetCommitted();
    setState(() => _live = content);
  }

  void _listenCache() {
    _cacheSub = ref.listenManual<AsyncValue<core.PageThumbnail?>>(
      core.pageThumbnailProvider(widget.page.id),
      (_, next) => _onCache(next),
      fireImmediately: true,
    );
  }

  void _onCache(AsyncValue<core.PageThumbnail?> value) {
    if (_live != null) return;
    switch (value) {
      case AsyncData(value: final core.PageThumbnail thumb):
        unawaited(_checkFresh(thumb));
      case AsyncData():
      case AsyncError(isLoading: false):
        unawaited(_loadOnce());
      default:
        break; // loading: placeholder
    }
  }

  Future<void> _checkFresh(core.PageThumbnail thumb) async {
    final generation = _generation;
    core.Page? committed;
    try {
      committed = await ref
          .read(core.noteContentReaderProvider)
          .getPage(widget.page.id);
    } on Object catch (error, stack) {
      _report(error, stack, 'while checking a page thumbnail');
    }
    if (!mounted || generation != _generation || _live != null) return;
    if (committed != null && !thumb.isStaleFor(committed)) {
      setState(() => _cached = thumb);
    } else {
      if (_cached != null) setState(() => _cached = null);
      await _loadOnce();
    }
  }

  Future<void> _loadOnce() async {
    if (_loadStarted) return;
    _loadStarted = true;
    final generation = _generation;
    try {
      final content = await ref
          .read(core.noteContentReaderProvider)
          .loadPage(widget.page.id);
      if (!mounted || generation != _generation || _live != null) return;
      setState(() => _loaded = content);
    } on core.EntityNotFoundException {
      // Deleted meanwhile: the list drops the item.
    } on Object catch (error, stack) {
      _report(error, stack, 'while loading a page thumbnail');
    }
  }

  void _report(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription(context),
      ),
    );
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builders = ref.watch(ink.pageBackgroundBuildersProvider);
    final grain = ref.watch(ink.pencilGrainProvider);
    final page = widget.page;
    final width = widget.width;
    final height = PagePanelThumbnail.heightFor(page.size, width);
    final content = _live ?? _loaded;
    final cached = _cached;
    final Widget child;
    if (content != null) {
      child = ink.InkPageThumbnail(
        content: ink.InkPageContent.fromCore(
          page: content.page,
          strokes: content.strokes,
          revision: content.revision,
        ),
        width: width,
        backgroundBuilders: builders,
        pencilGrain: grain,
      );
    } else if (cached != null) {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      child = Image.memory(
        cached.bytes,
        key: PagePanelThumbnail.imageKey,
        width: width,
        height: width * page.size.height / page.size.width,
        fit: BoxFit.fill,
        cacheWidth: math.max(1, (width * dpr).round()),
        gaplessPlayback: true,
      );
    } else {
      return SizedBox(
        key: PagePanelThumbnail.placeholderKey,
        width: width,
        height: height,
        child: ColoredBox(color: Color(page.background.paperColorArgb)),
      );
    }
    // Pages taller than maxHeight show their top part.
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: double.infinity,
            child: child,
          ),
        ),
      ),
    );
  }
}
