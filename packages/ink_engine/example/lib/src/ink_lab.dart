// ink lab: one page of a note on the CORE fake store, wired the way EDITOR
// wires INK (03-ink 5.3) — every pointer sample through InkSampleAdapter, one
// gesture = one session = one InkEdit = one session.execute(edit.toCommand()),
// discardEdit on a failed commit, every pageChanges event →
// controller.updateContent. The controller comes from
// inkPageControllerProvider (a ProviderContainer with core.noteStoreProvider
// overridden by createFakeNoteStore()).
import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:riverpod/riverpod.dart';

import 'stats_panel.dart';

/// What a stylus / mouse (and a finger when allowed) does on the page.
enum LabTool {
  ballpoint('Ballpoint', core.PenTool.ballpoint),
  fountain('Fountain', core.PenTool.fountain),
  highlighter('Highlighter', core.PenTool.highlighter),
  pencil('Pencil', core.PenTool.pencil),
  marker('Marker', core.PenTool.marker),
  strokeEraser('Stroke eraser', null),
  partialEraser('Partial eraser', null),
  lasso('Lasso', null);

  const LabTool(this.label, this.pen);
  final String label;
  final core.PenTool? pen;
}

/// The page backgrounds ink lab cycles through (03-ink 9.3 #12).
const List<core.PageTemplateKind?> labTemplates = [
  null, // blank
  core.PageTemplateKind.lined,
  core.PageTemplateKind.grid,
  core.PageTemplateKind.dotted,
  core.PageTemplateKind.cornell,
  core.PageTemplateKind.music,
  core.PageTemplateKind.planner,
];

const double _strokeEraserRadiusPt = 8;
const double _partialEraserRadiusPt = 3;

class InkLabApp extends StatelessWidget {
  const InkLabApp({super.key, this.store});

  /// The store to draw into (tests); null → a new createFakeNoteStore().
  final core.NoteStore? store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ink lab',
    theme: ThemeData(),
    home: InkLabPage(store: store),
  );
}

class InkLabPage extends StatefulWidget {
  const InkLabPage({super.key, this.store});

  final core.NoteStore? store;

  @override
  State<InkLabPage> createState() => InkLabPageState();
}

/// Public for the smoke test (example/test/smoke_test.dart).
class InkLabPageState extends State<InkLabPage> {
  late final core.NoteStore _store =
      widget.store ?? core_testing.createFakeNoteStore();
  late final ProviderContainer _container = ProviderContainer(
    overrides: [core.noteStoreProvider.overrideWithValue(_store)],
  );

  core.NoteSession? _session;
  String? _pageId;
  ProviderSubscription<InkPageController>? _controllerSub;
  StreamSubscription<core.PageContentChange>? _changes;
  Object? _openError;

  LabTool _tool = LabTool.fountain;
  bool _fingerDraws = false;
  bool _highlighterOnly = false;
  bool _showStats = true;
  double _zoom = 1;
  int _templateIndex = 0;
  bool _darkPaper = false;
  String? _message;

  // the gesture in progress (one pointer at a time)
  int? _pointer;
  double _gestureViewScale = 1;
  InkGestureSession? _gesture;
  Offset? _moveStart;

  InkPageController? get controller => _controllerSub?.read();
  core.NoteSession? get session => _session;
  String? get pageId => _pageId;
  LabTool get tool => _tool;
  InkDiagnostics get diagnostics => _container.read(inkDiagnosticsProvider);

  @override
  void initState() {
    super.initState();
    diagnostics.enabled = _showStats;
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final note = await _store.library.createNote(title: 'ink lab');
      final session = await _store.openSession(note.id);
      final pageId = session.pages.first.id;
      final content = await session.openPage(pageId);
      if (!mounted) {
        await session.close();
        return;
      }
      final sub = _container.listen(
        inkPageControllerProvider(pageId),
        (_, _) {},
      );
      final c = sub.read()..updateContent(_inkContentOf(content));
      setState(() {
        _session = session;
        _pageId = pageId;
        _controllerSub = sub;
        _changes = session
            .pageChanges(pageId)
            .listen((change) => c.updateContent(_inkContentOf(change.content)));
      });
    } on Object catch (e) {
      if (mounted) setState(() => _openError = e);
    }
  }

  static InkPageContent _inkContentOf(core.PageContent c) =>
      InkPageContent.fromCore(
        page: c.page,
        strokes: c.strokes,
        revision: c.revision,
      );

  @override
  void dispose() {
    _gesture?.cancel();
    unawaited(_changes?.cancel());
    _controllerSub?.close();
    diagnostics.enabled = false;
    _container.dispose();
    final session = _session;
    unawaited(() async {
      await session?.close();
      if (widget.store == null) await _store.close();
    }());
    super.dispose();
  }

  // --- commands -------------------------------------------------------------

  void _commit(InkEdit? edit) {
    final s = _session, c = controller;
    if (edit == null || s == null || c == null) return;
    try {
      s.execute(edit.toCommand());
    } on Object catch (e) {
      c.discardEdit(edit); // contract 7.2.15 '커밋 실패'
      _say('Commit failed: $e');
    }
  }

  void _execute(core.EditCommand command) {
    final s = _session;
    if (s == null) return;
    try {
      s.execute(command);
    } on Object catch (e) {
      _say('$e');
    }
  }

  void _say(String message) => setState(() => _message = message);

  void _addSynthetic(int count) {
    final s = _session, id = _pageId;
    if (s == null || id == null) return;
    final page = s.pageIfLoaded(id)!.page;
    controller?.clearSelection();
    _execute(
      core.AddStrokes(
        pageId: id,
        strokes: InkDevTools.syntheticStrokes(
          pageId: id,
          pageSize: page.size,
          count: count,
          newId: _store.ids.newId,
          createdAt: _store.clock.now().millisecondsSinceEpoch,
          seed: count + page.contentRevision,
        ),
      ),
    );
    _say('Added $count synthetic strokes');
  }

  void _setBackground({int? templateIndex, bool? dark}) {
    final id = _pageId;
    if (id == null) return;
    _templateIndex = templateIndex ?? _templateIndex;
    _darkPaper = dark ?? _darkPaper;
    final paper = _darkPaper ? core.PaperColors.black : core.PaperColors.white;
    final kind = labTemplates[_templateIndex];
    _execute(
      core.SetPageBackground(
        pageIds: [id],
        background: kind == null
            ? core.BlankBackground(paperColorArgb: paper)
            : core.TemplateBackground(
                template: core.PageTemplate.defaults(kind),
                paperColorArgb: paper,
              ),
      ),
    );
    setState(() {});
  }

  Future<void> _undoRedo({required bool undo}) async {
    final s = _session;
    if (s == null) return;
    controller?.clearSelection();
    try {
      if (undo) {
        await s.undo();
      } else {
        await s.redo();
      }
    } on Object catch (e) {
      _say('$e');
    }
  }

  void _deleteSelection() {
    final sel = controller?.selection;
    if (sel == null || sel.isEmpty || sel.isDisposed) return;
    _commit(sel.delete());
    controller?.clearSelection();
  }

  void _cyclePressureMode() {
    final n = _container.read(pressureModeProvider.notifier);
    const modes = PressureMode.values;
    final next =
        modes[(modes.indexOf(_container.read(pressureModeProvider)) + 1) %
            modes.length];
    n.set(next);
    _say('Pressure mode: ${next.name}');
  }

  // --- pointer input (EDITOR's role) ----------------------------------------

  bool _draws(PointerDeviceKind kind) =>
      kind != PointerDeviceKind.touch || _fingerDraws;

  InkSample _sampleOf(PointerEvent e) => InkSampleAdapter.fromPointerEvent(
    e,
    pagePosition: e.localPosition / _gestureViewScale,
  );

  void _onDown(PointerDownEvent e, double viewScale) {
    final c = controller;
    if (c == null || _pointer != null || !_draws(e.kind)) return;
    _pointer = e.pointer;
    _gestureViewScale = viewScale;
    final sample = _sampleOf(e);
    final tool = e.kind == PointerDeviceKind.invertedStylus
        ? LabTool.strokeEraser
        : _tool;
    final filter = _highlighterOnly
        ? core.StrokeFilter.highlighterOnly
        : core.StrokeFilter.all;
    switch (tool) {
      case LabTool.strokeEraser || LabTool.partialEraser:
        c.clearSelection();
        _gesture = c.beginErase(
          sample,
          spec: EraserSpec(
            mode: tool == LabTool.strokeEraser
                ? EraserMode.stroke
                : EraserMode.partial,
            radius: tool == LabTool.strokeEraser
                ? _strokeEraserRadiusPt
                : _partialEraserRadiusPt,
            filter: filter,
          ),
          viewScale: viewScale,
        );
      case LabTool.lasso:
        final sel = c.selection;
        if (sel != null &&
            !sel.isEmpty &&
            sel.bounds.inflate(8).contains(sample.position)) {
          _moveStart = sample.position; // drag the selection
        } else {
          c.clearSelection();
          _gesture = c.beginLasso(sample.position, viewScale: viewScale);
        }
      case _:
        c.clearSelection();
        _gesture = c.beginStroke(
          sample,
          style: core.StrokeStyle.defaultsFor(tool.pen!),
          viewScale: viewScale,
        );
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final sample = _sampleOf(e);
    final start = _moveStart;
    if (start != null) {
      final d = sample.position - start;
      controller?.selection?.setPreviewTransform(
        core.Affine2.translation(d.dx, d.dy),
      );
      return;
    }
    switch (_gesture) {
      case final StrokeSession s when s.isActive:
        s.addSample(sample);
      case final EraserSession s when s.isActive:
        s.addSample(sample);
      case final LassoSession s when s.isActive:
        s.addPoint(sample.position);
      case _:
    }
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final sample = _sampleOf(e);
    final gesture = _gesture;
    _pointer = null;
    _gesture = null;
    if (_moveStart != null) {
      _moveStart = null;
      _commit(controller?.selection?.commitTransform());
      return;
    }
    switch (gesture) {
      case final StrokeSession s when s.isActive:
        _commit(s.end(sample));
      case final EraserSession s when s.isActive:
        _commit(s.end(sample));
      case final LassoSession s when s.isActive:
        s.addPoint(sample.position);
        final sel = s.end();
        if (sel != null) _say('Selected ${sel.strokeIds.length} strokes');
        setState(() {});
      case _:
    }
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _gesture?.cancel();
    _gesture = null;
    if (_moveStart != null) {
      _moveStart = null;
      controller?.selection?.setPreviewTransform(core.Affine2.identity);
    }
  }

  // --- UI ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('ink lab')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(context),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _message!,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: _openError != null
                  ? Center(child: Text('Could not open the note: $_openError'))
                  : c == null
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        Positioned.fill(child: _pageArea(c, scheme)),
                        if (_showStats)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: IgnorePointer(
                              child: InkStatsPanel(diagnostics: diagnostics),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final t in LabTool.values)
          ChoiceChip(
            key: ValueKey('tool-${t.name}'),
            label: Text(t.label),
            selected: _tool == t,
            onSelected: (_) => setState(() {
              _tool = t;
              if (t != LabTool.lasso) controller?.clearSelection();
            }),
          ),
        FilterChip(
          key: const ValueKey('highlighter-only'),
          label: const Text('Erase highlighter only'),
          selected: _highlighterOnly,
          onSelected: (v) => setState(() => _highlighterOnly = v),
        ),
        FilterChip(
          key: const ValueKey('finger-draws'),
          label: const Text('Finger draws'),
          selected: _fingerDraws,
          onSelected: (v) => setState(() => _fingerDraws = v),
        ),
        ActionChip(
          key: const ValueKey('pressure-mode'),
          label: Text(
            'Pressure: ${_container.read(pressureModeProvider).name}',
          ),
          onPressed: _cyclePressureMode,
        ),
        ActionChip(
          key: const ValueKey('delete-selection'),
          label: const Text('Delete selection'),
          onPressed: _deleteSelection,
        ),
        ActionChip(
          key: const ValueKey('undo'),
          label: const Text('Undo'),
          onPressed: () => unawaited(_undoRedo(undo: true)),
        ),
        ActionChip(
          key: const ValueKey('redo'),
          label: const Text('Redo'),
          onPressed: () => unawaited(_undoRedo(undo: false)),
        ),
        ActionChip(
          key: const ValueKey('clear'),
          label: const Text('Clear'),
          onPressed: () {
            final id = _pageId;
            controller?.clearSelection();
            if (id != null) _execute(core.ClearPage(pageId: id));
          },
        ),
        ActionChip(
          key: const ValueKey('synthetic-1000'),
          label: const Text('+1,000 strokes'),
          onPressed: () => _addSynthetic(1000),
        ),
        ActionChip(
          key: const ValueKey('synthetic-3000'),
          label: const Text('+3,000 strokes'),
          onPressed: () => _addSynthetic(3000),
        ),
        ActionChip(
          key: const ValueKey('template'),
          label: Text(
            'Paper: ${labTemplates[_templateIndex]?.name ?? 'blank'}',
          ),
          onPressed: () => _setBackground(
            templateIndex: (_templateIndex + 1) % labTemplates.length,
          ),
        ),
        FilterChip(
          key: const ValueKey('dark-paper'),
          label: const Text('Dark paper'),
          selected: _darkPaper,
          onSelected: (v) => _setBackground(dark: v),
        ),
        for (final z in const [1.0, 2.0, 4.0])
          ChoiceChip(
            key: ValueKey('zoom-${z.round()}'),
            label: Text('${z.toStringAsFixed(0)}×'),
            selected: _zoom == z,
            onSelected: (_) => setState(() => _zoom = z),
          ),
        FilterChip(
          key: const ValueKey('stats'),
          label: const Text('Developer numbers'),
          selected: _showStats,
          onSelected: (v) => setState(() {
            _showStats = v;
            diagnostics.enabled = v;
          }),
        ),
      ],
    ),
  );

  Widget _pageArea(InkPageController c, ColorScheme scheme) => LayoutBuilder(
    builder: (context, box) {
      final content = c.content;
      if (content == null) return const SizedBox.shrink();
      const margin = 16.0;
      final fitWidth = (box.maxWidth - 2 * margin).clamp(1.0, double.infinity);
      final fitScale = fitWidth / content.pageSize.width;
      final viewScale = fitScale * _zoom;
      final pageWidth = content.pageSize.width * viewScale;
      // fingers scroll (unless they draw); the stylus and the mouse draw
      final scroll = ScrollConfiguration.of(context).copyWith(
        dragDevices: _fingerDraws
            ? const <PointerDeviceKind>{}
            : const {PointerDeviceKind.touch, PointerDeviceKind.trackpad},
        scrollbars: false,
      );
      return ColoredBox(
        color: scheme.surfaceContainer,
        child: ScrollConfiguration(
          behavior: scroll,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(margin),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: pageWidth,
                child: Listener(
                  key: const ValueKey('page'),
                  onPointerDown: (e) => _onDown(e, viewScale),
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onCancel,
                  child: InkPageView(controller: c),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
