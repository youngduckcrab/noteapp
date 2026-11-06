// E-22: performance smoke test (04-editor 6.15 #9, VM): 500-page layout
// < 5 ms, 10,000 range queries < 20 ms, 10,000 router events < 50 ms, one pen
// stroke committed on a page of 5,000 strokes (execute + INK updateContent,
// fake CORE store + INK foundation implementation) < 5 ms.
//
// (v2, E2-22 — m5-7/04-editor 6.22) The 2nd-round paths, each figure the
// whole path including its INK calls (INK is not taken out — there is no
// fake INK; the INK of this work tree is the foundation implementation, so
// the real INK v2 figures come with the integration stage):
// - the pen-down extra cost (the contact rule + the gesture at contact +
//   the recording meta while recording) 10,000 times < 20 ms (the barrel
//   roll angle is E2-18 — P-B — and joins this figure when it lands);
// - one playback highlight frame's EDITOR share (positionMs + the logic +
//   setPlaybackFocus on 8 mounted page controllers) 1,000 times < 50 ms;
// - one rotate preview of a mixed selection of everything on a page of
//   5,000 strokes + 200 objects (the angle, snapAngle, setPreviewTransform)
//   < 2 ms;
// - 1,000 moves of a shape drag (the real ShapeInteraction: screenToPage,
//   ShapeDrafts.geometry, setPreviewObjects) < 30 ms;
// - a paste's instantiate of 2,000 strokes + 200 objects < 20 ms;
// - typing one character in a text edit session rebuilds no page slot of
//   PageViewport (EditorPageView) and not PageViewport itself (build count
//   — debugOnRebuildDirtyWidget).
//
// Other agents share this container's CPUs, so each figure is the best of
// [_runs] measured runs after a warm-up (a busy CPU slows single runs, not
// the best one); the limits are 6.15's / 6.22's as written. No timers, no
// waiting: the CORE fake runs on microtasks inside fakeAsync, the router gets
// a timer factory that never fires.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/src/document/mounted_pages.dart';
import 'package:feature_editor/src/document/page_mount.dart';
import 'package:feature_editor/src/input/input_router.dart';
import 'package:feature_editor/src/input/input_sample.dart';
import 'package:feature_editor/src/input/input_targets.dart';
import 'package:feature_editor/src/input/stylus_contact.dart';
import 'package:feature_editor/src/playback/playback_highlighter.dart';
import 'package:feature_editor/src/playback/recording_link.dart';
import 'package:feature_editor/src/state/settings/editor_settings.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_box_placement.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/tools/element_clipboard.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/selection_transform_interaction.dart';
import 'package:feature_editor/src/tools/shape_drafts.dart';
import 'package:feature_editor/src/tools/shape_interaction.dart';
import 'package:feature_editor/src/tools/tool_interaction.dart';
import 'package:feature_editor/src/tools/tool_options.dart';
import 'package:feature_editor/src/viewport/editor_page_view.dart';
import 'package:feature_editor/src/viewport/page_layout.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:feature_editor/src/viewport/viewport_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:material_ui/material_ui.dart'
    show TextField, TextSelection, debugOnRebuildDirtyWidget;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// Measured runs per figure (after one warm-up run).
const int _runs = 5;

/// Best (shortest) of [_runs] results of [measure] (milliseconds), after a
/// warm-up call that is not counted.
double _best(double Function() measure) {
  measure(); // warm-up (JIT, allocations)
  var best = double.infinity;
  for (var i = 0; i < _runs; i++) {
    final ms = measure();
    if (ms < best) best = ms;
  }
  return best;
}

/// Milliseconds [body] takes.
double _timeMs(void Function() body) {
  final sw = Stopwatch()..start();
  body();
  sw.stop();
  return sw.elapsedMicroseconds / 1000;
}

/// Best of [_runs] timed runs of [body] (milliseconds).
double _bestMs(void Function() body) => _best(() => _timeMs(body));

/// Mixed page sizes (A4 portrait / landscape, letter, 16:9) — 500 of them.
final List<Size> _sizes500 = [
  for (var i = 0; i < 500; i++)
    switch (i % 4) {
      0 => const Size(595.2756, 841.8898),
      1 => const Size(841.8898, 595.2756),
      2 => const Size(612, 792),
      _ => const Size(960, 540),
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('500-page layout < 5 ms', () {
    late PageLayout layout;
    final ms = _bestMs(() {
      layout = PageLayout.compute(
        pageSizes: _sizes500,
        axis: LayoutAxis.vertical,
      );
    });
    expect(layout.length, 500);
    expect(ms, lessThan(5), reason: '500-page layout took $ms ms');
  });

  test('10,000 range queries < 20 ms', () {
    final layout = PageLayout.compute(
      pageSizes: _sizes500,
      axis: LayoutAxis.vertical,
    );
    final height = layout.contentSize.height;
    var hits = 0;
    final ms = _bestMs(() {
      hits = 0;
      for (var i = 0; i < 10000; i++) {
        // A screen-sized window sliding over the whole note.
        final top = (i * 7919.0) % height;
        final range = layout.rangeIntersecting(
          Rect.fromLTWH(0, top, 1000, 1250),
        );
        if (range != null) hits++;
      }
    });
    expect(hits, greaterThan(9000));
    expect(ms, lessThan(20), reason: '10,000 range queries took $ms ms');
  });

  test('10,000 router events < 50 ms', () {
    final targets = _CountingTargets();
    final router = InputRouter(
      targets: targets,
      timerFactory: (_, _) => _NeverTimer(),
    );
    final events = _stylusStrokes(10000);
    final ms = _bestMs(() {
      for (final e in events) {
        router.handlePointerEvent(e);
      }
    });
    router.cancelAll();
    // Every stroke reached the tool: begin, the moves, end.
    expect(targets.begun, (_runs + 1) * (events.length ~/ _strokeLength));
    expect(targets.ended, targets.begun);
    expect(targets.observed, (_runs + 1) * events.length); // every event
    expect(ms, lessThan(50), reason: '10,000 router events took $ms ms');
  });

  test('pen stroke commit on a 5,000-stroke page < 5 ms', () {
    fakeAsync((async) {
      final env = _CommitEnv(async)..open(strokeCount: 5000);
      try {
        final controller = env.controller;
        expect(controller.content!.strokes.length, 5000);
        var made = 0;
        var y = 20.0;
        final ms = _best(() {
          // The stroke is drawn outside the measurement, as the pen does it;
          // the commit is what 6.7 runs on pen up: execute → (inside it) the
          // page change → controller.updateContent.
          final edit = env.drawStroke(y += 3);
          final took = _timeMs(() => env.session.execute(edit.toCommand()));
          made++;
          expect(controller.pendingIds, isEmpty); // updateContent resolved it
          return took;
        });
        expect(controller.content!.strokes.length, 5000 + made);
        expect(env.session.history.undoDepth, made);
        expect(ms, lessThan(5), reason: 'commit on 5,000 strokes took $ms ms');
      } finally {
        env.dispose();
      }
    });
  });

  // ---- v2 (E2-22, m5-7/04-editor 6.22) ------------------------------------

  test('v2: pen-down extra cost (contact + gesture at contact + recording '
      'meta) 10,000 times < 20 ms', () {
    fakeAsync((async) {
      final store = createFakeNoteStore();
      final recorder = FakeAudioRecorder(store: store);
      unawaited(recorder.start(recordingId: 'rec-1', noteId: _noteId));
      async.flushMicrotasks();
      recorder.advance(const Duration(milliseconds: 1200));
      expect(recorder.status.phase, core.RecorderPhase.recording);
      // A stylus contact as the router sees it (native: the down; web: the
      // contact move — both rules measured).
      final downs = [
        for (var i = 0; i < 100; i++)
          PointerDownEvent(
            pointer: i + 1,
            kind: PointerDeviceKind.stylus,
            position: Offset(100.0 + i, 200),
            buttons: kStylusContact | (i.isEven ? 0 : kPrimaryStylusButton),
            pressure: 0.5,
          ),
      ];
      var linked = 0;
      var buttons = 0;
      final ms = _bestMs(() {
        linked = 0;
        buttons = 0;
        for (var i = 0; i < 10000; i++) {
          final e = downs[i % downs.length];
          final rule = i.isEven
              ? StylusContactRule.native
              : StylusContactRule.web;
          if (!StylusContact.isContact(rule, e)) continue;
          if (StylusContact.gestureAtContact(e) != null) buttons++;
          final meta = RecordingLink.metaFor(
            recorder,
            _noteId,
            core.PenTool.ballpoint,
          );
          if (meta.recordingId != null) linked++;
        }
      });
      expect(linked, 10000);
      expect(buttons, 5000);
      expect(ms, lessThan(20), reason: '10,000 pen downs took $ms ms');
      unawaited(recorder.stop());
      unawaited(store.close());
      async.flushMicrotasks();
    });
  });

  test('v2: one playback highlight frame (positionMs + the logic + '
      'setPlaybackFocus on 8 mounted pages) 1,000 times < 50 ms', () {
    final controllers = [
      for (var i = 0; i < 8; i++)
        ink_testing.createTestPageController(pageId: 'perf-pb$i'),
    ];
    final playback = FakeAudioPlayback();
    var outputs = 0;
    final logic = PlaybackHighlightLogic(
      output: (focus) {
        outputs++;
        for (final c in controllers) {
          c.setPlaybackFocus(focus);
        }
      },
      noteRecordingIds: () => const {'rec-1'},
      style: () => const EditorSettings().playbackHighlight,
    );
    try {
      fakeAsync((async) {
        unawaited(
          playback.open(
            const core.Recording(
              id: 'rec-1',
              noteId: _noteId,
              assetId: 'asset-1',
              durationMs: 3600000,
              startedAt: 0,
              createdAt: 0,
              updatedAt: 0,
            ),
          ),
        );
        unawaited(playback.play());
        async.flushMicrotasks();
      });
      expect(
        logic.onStatus(playback.status, positionMs: playback.positionMs()),
        isTrue,
      );
      var position = 0;
      final ms = _bestMs(() {
        for (var i = 0; i < 1000; i++) {
          playback.setPositionMs(position += 16); // one frame at 60 Hz
          logic.onTick(playback.positionMs());
        }
      });
      expect(logic.current!.positionMs, position);
      expect(outputs, 1 + (_runs + 1) * 1000); // every frame moved on
      for (final c in controllers) {
        expect(c.playbackFocus, logic.current);
      }
      expect(ms, lessThan(50), reason: '1,000 highlight frames took $ms ms');
    } finally {
      for (final c in controllers) {
        c.dispose();
      }
    }
  });

  test('v2: a rotate preview of everything on a page of 5,000 strokes + 200 '
      'objects < 2 ms', () {
    fakeAsync((async) {
      final env = _CommitEnv(async)..open(strokeCount: 5000, objectCount: 200);
      final viewport = _viewportOf([env.session.pages.single]);
      final pages = MountedPages()..register(env.mount);
      try {
        final controller = env.controller;
        final content = controller.content!;
        expect(content.strokes.length, 5000);
        expect(content.objects.length, 200);
        final all = {
          for (final s in content.strokes) s.id,
          for (final o in content.objects) o.id,
        };
        final sel = controller.select(all);
        final selection = EditorSelection(pageId: _pageId, elementIds: all);
        expect(sel.allIds.length, 5200);
        // What SelectionTransformInteraction does on a rotate move (bounds
        // and centre are taken at the down): the turned angle, the 15° snap,
        // the rotation about the centre, setPreviewTransform (6.22 — the
        // frame painted for it is INK's bounds through the viewport, checked
        // once below, not timed: on the foundation INK that read sorts the
        // 5,000 strokes — about 2 ms here, an integration-stage figure).
        final bounds = sel.bounds;
        final centre = bounds.center;
        final down = bounds.topCenter - centre;
        var step = 0;
        final ms = _best(() {
          final turned = (++step * 7.3) * math.pi / 180;
          final now = Offset.fromDirection(down.direction + turned, 100);
          return _timeMs(() {
            final radians = ink.SelectionGeometry.snapAngle(
              normalizeAngle(now.direction - down.direction),
            );
            sel.setPreviewTransform(
              core.Affine2.rotation(
                radians,
                originX: centre.dx,
                originY: centre.dy,
              ),
            );
          });
        });
        expect(sel.previewTransform.isIdentity, isFalse);
        expect(ms, lessThan(2), reason: 'a rotate preview took $ms ms');
        // The frame of the turned selection: 4 corners and the rotate handle
        // on INK's bounds turned by the preview.
        final frame = selectionFrameOnScreen(viewport, pages, selection)!;
        expect(frame.rotatable, isTrue);
        expect(frame.handles, hasLength(4));
        final corners = ink.SelectionGeometry.transformedCorners(
          bounds,
          sel.previewTransform,
        );
        expect(
          (frame.quad.topLeft - viewport.pageToScreen(0, corners[0])).distance,
          lessThan(1e-6),
        );
        sel.setPreviewTransform(core.Affine2.identity);
      } finally {
        pages.dispose();
        env.dispose();
        async.elapse(const Duration(seconds: 1)); // the settle timer
        viewport.dispose();
      }
    });
  });

  test('v2: 1,000 moves of a shape drag (ShapeInteraction — '
      'ShapeDrafts.geometry + setPreviewObjects) < 30 ms', () {
    fakeAsync((async) {
      final viewport = _viewportOf([_page]);
      final controller = ink_testing.createTestPageController(pageId: _pageId);
      try {
        for (final kind in [core.ShapeKind.rectangle, core.ShapeKind.star]) {
          var moved = 0;
          final ms = _bestMs(() {
            final start = viewport.pageToScreen(0, const Offset(100, 100));
            final drag = ShapeInteraction.start(
              down: InputSample(
                PointerDownEvent(
                  pointer: 1,
                  kind: PointerDeviceKind.stylus,
                  position: start,
                ),
              ),
              source: InteractionSource.stylus,
              controller: controller,
              pageId: _pageId,
              pageIndex: 0,
              options: ToolOptions(shapeKind: kind),
              viewport: viewport,
              snap: () => ShapeSnap.normal,
              onCommit: (_, _, _) {},
              onTap: (_) {},
            );
            for (var i = 1; i <= 1000; i++) {
              drag.move(
                InputSample(
                  PointerMoveEvent(
                    pointer: 1,
                    kind: PointerDeviceKind.stylus,
                    position: start + Offset(i * 0.4, i * 0.3),
                  ),
                ),
              );
              moved++;
            }
            drag.cancel();
          });
          expect(moved, (_runs + 1) * 1000);
          expect(controller.previewObjects, isEmpty); // cancel cleared it
          expect(ms, lessThan(30), reason: '1,000 $kind moves took $ms ms');
        }
      } finally {
        controller.dispose();
        async.elapse(const Duration(seconds: 1)); // the settle timer
        viewport.dispose();
      }
    });
  });

  test('v2: paste instantiate of 2,000 strokes + 200 objects < 20 ms', () {
    final container = ProviderContainer();
    try {
      final clipboard = container.read(editorClipboardProvider.notifier);
      clipboard.copy([
        for (var i = 0; i < 2000; i++) _stroke(i),
        for (var i = 0; i < 200; i++) _object(i),
      ]);
      expect(container.read(editorClipboardProvider)!.objectCount, 200);
      var ids = 0;
      late ({List<core.Stroke> strokes, List<core.PageObject> objects}) made;
      final ms = _bestMs(() {
        made = clipboard.instantiate(
          pageId: 'perf-target',
          pageSize: const Size(595.2756, 841.8898),
          center: const Offset(300, 400),
          explicitPoint: false,
          newId: () => 'perf-new-${ids++}',
          createdAt: 10000,
        );
      });
      expect(made.strokes, hasLength(2000));
      expect(made.objects, hasLength(200));
      expect(made.objects.first.pageId, 'perf-target');
      expect(ms, lessThan(20), reason: 'instantiate took $ms ms');
    } finally {
      container.dispose();
    }
  });

  testWidgets('v2: typing a character in a text edit session rebuilds no '
      'page slot (EditorPageView) and not PageViewport', (tester) async {
    await ink_testing.useInkTestFonts();
    final h = await pumpEditor(tester);
    final notifier = h.container.read(editorTextEditProvider.notifier);
    notifier.start(
      newTextBoxAt(
        id: 'perf-tb',
        pageId: h.pageId(0),
        point: const Offset(100, 100),
        pageWidth: 595,
        style: const core.TextBoxStyle(),
        createdAt: 1,
      ),
      isNew: true,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(textEditorKey), findsOneWidget);
    expect(find.byType(EditorPageView), findsWidgets);

    final rebuilt = <Type, int>{};
    final previous = debugOnRebuildDirtyWidget;
    // Every build while typing (the callback's builtOnce flag is only kept
    // with debugPrintRebuildDirtyWidgets on — a page slot must not build at
    // all, first build or not).
    debugOnRebuildDirtyWidget = (element, _) {
      final type = element.widget.runtimeType;
      rebuilt[type] = (rebuilt[type] ?? 0) + 1;
    };
    try {
      for (final text in ['a', 'ab', 'abc']) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pump();
        expect(h.container.read(editorTextEditProvider)!.draft.text, text);
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    expect(rebuilt[EditorPageView] ?? 0, 0, reason: '$rebuilt');
    expect(rebuilt[PageViewport] ?? 0, 0, reason: '$rebuilt');
    // The count is live: the editor's own field did rebuild …
    expect(rebuilt[TextField] ?? 0, greaterThan(0), reason: '$rebuilt');
    await notifier.end(reason: TextEditEndReason.escape);
    await tester.pump();

    // … and a page slot rebuild is seen when there is one (a settled zoom
    // gives the slots a new scale).
    rebuilt.clear();
    debugOnRebuildDirtyWidget = (element, _) {
      final type = element.widget.runtimeType;
      rebuilt[type] = (rebuilt[type] ?? 0) + 1;
    };
    try {
      h.viewport
        ..zoomBy(2, const Offset(516, 688))
        ..settleNow();
      await tester.pump();
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    expect(rebuilt[EditorPageView] ?? 0, greaterThan(0), reason: '$rebuilt');
  });
}

// ---- router ------------------------------------------------------------------

/// Points per synthetic stroke (down, moves, up).
const int _strokeLength = 100;

/// [count] pointer events: stylus strokes of [_strokeLength] events each.
List<PointerEvent> _stylusStrokes(int count) {
  final events = <PointerEvent>[];
  var pointer = 1;
  var t = 0;
  while (events.length < count) {
    pointer++;
    for (var i = 0; i < _strokeLength; i++) {
      t += 4000; // 4 ms apart (240 Hz)
      final position = Offset(100.0 + i * 3, 200.0 + (pointer % 50) * 10);
      final stamp = Duration(microseconds: t);
      events.add(
        i == 0
            ? PointerDownEvent(
                pointer: pointer,
                kind: PointerDeviceKind.stylus,
                position: position,
                timeStamp: stamp,
                pressure: 0.5,
              )
            : i == _strokeLength - 1
            ? PointerUpEvent(
                pointer: pointer,
                kind: PointerDeviceKind.stylus,
                position: position,
                timeStamp: stamp,
              )
            : PointerMoveEvent(
                pointer: pointer,
                kind: PointerDeviceKind.stylus,
                position: position,
                timeStamp: stamp,
                pressure: 0.5,
              ),
      );
    }
  }
  return events;
}

/// InputTargets that only counts (the router's own cost is measured).
final class _CountingTargets implements InputTargets {
  int begun = 0;
  int ended = 0;
  int observed = 0;

  @override
  InputPolicy get policy => const InputPolicy(
    penOnly: false,
    palm: PalmRejectionSettings(),
    gestures: GestureSettings.defaults,
    stylusSeen: true,
    eyedropperActive: false,
  );

  @override
  ToolInteraction? beginInteraction(
    InputSample sample, {
    required InteractionSource source,
    EditorGesture? gesture,
  }) {
    begun++;
    return _CountingInteraction(this, source, sample.timeStamp);
  }

  @override
  bool hitsSelection(Offset screen) => false;
  @override
  bool interceptPenDot(
    InputSample sample, {
    required InteractionSource source,
  }) => false;
  @override
  void navigationStart() {}
  @override
  void navigationUpdate(NavigationUpdate update) {}
  @override
  void navigationEnd(Velocity velocity) {}
  @override
  void navigationCancel() {}
  @override
  void tapGesture(int fingerCount, Offset centroid) {}
  @override
  void longPress(Offset screen) {}
  @override
  void secondaryClick(Offset screen) {}
  @override
  void hover(InputSample sample) {}
  @override
  void scrollSignal(Offset scrollDelta, Offset at, {required bool zoom}) {}
  @override
  void panZoomSignal({
    required Offset panDelta,
    required double scaleFactor,
    required Offset focal,
  }) {}
  @override
  void stylusDetected() {}
  @override
  void palmRejected(InputSample sample) {}
  @override
  void observe(PointerEvent event, InputSample sample) => observed++;
}

final class _CountingInteraction extends ToolInteraction {
  _CountingInteraction(this._targets, InteractionSource source, Duration at)
    : super(source: source, startedAt: at);
  final _CountingTargets _targets;
  var _travelled = 0.0;

  @override
  double get travelled => _travelled;
  @override
  void move(InputSample sample) => _travelled += 1;
  @override
  void end(InputSample sample) => _targets.ended++;
  @override
  void cancel() {}
}

/// A timer that never fires (long-press timers are not part of the cost).
final class _NeverTimer implements Timer {
  bool _active = true;
  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

// ---- commit ------------------------------------------------------------------

const String _pageId = 'perf-p0';
const String _noteId = 'perf-note';

/// Fake CORE store + one open page of [open]'s strokes + an INK foundation
/// controller fed by a PageMount (the editor's own path, 6.4.4).
final class _CommitEnv {
  _CommitEnv(this.async);

  final FakeAsync async;
  late final core.NoteStore store;
  late final core.NoteSession session;
  late final ink.InkPageController controller;
  late final PageMount mount;
  var _timeUs = 0;

  void open({required int strokeCount, int objectCount = 0}) {
    store = createFakeNoteStore();
    late core.Note note;
    unawaited(
      store.library
          .createNote(
            title: 'perf',
            pages: [
              const core.PageDraft(
                id: _pageId,
                size: kA4,
                background: core.BlankBackground(),
              ),
            ],
          )
          .then((n) => note = n),
    );
    async.flushMicrotasks();
    unawaited(store.openSession(note.id).then((s) => session = s));
    async.flushMicrotasks();
    unawaited(session.openPage(_pageId));
    async.flushMicrotasks();
    // 5,000 short strokes over the page, added in batches like a long note.
    const batch = 500;
    for (var start = 0; start < strokeCount; start += batch) {
      session.execute(
        core.AddStrokes(
          pageId: _pageId,
          strokes: [
            for (var i = start; i < start + batch && i < strokeCount; i++)
              lineStroke(
                id: 'perf-s$i',
                pageId: _pageId,
                x0: 20.0 + (i % 50) * 11,
                y0: 20.0 + (i ~/ 50) * 8,
                x1: 28.0 + (i % 50) * 11,
                y1: 24.0 + (i ~/ 50) * 8,
                pointCount: 12,
                createdAt: i,
              ),
          ],
        ),
      );
    }
    // (v2) [objectCount] shapes and text boxes over the page.
    for (var start = 0; start < objectCount; start += batch) {
      session.execute(
        core.AddObjects(
          pageId: _pageId,
          objects: [
            for (var i = start; i < start + batch && i < objectCount; i++)
              _object(i, pageId: _pageId),
          ],
        ),
      );
    }
    session
      ..closePage(_pageId)
      ..clearHistory();
    controller = ink_testing.createTestPageController(pageId: _pageId);
    mount = PageMount(
      session: session,
      page: session.pages.single,
      controller: controller,
    );
    async.flushMicrotasks();
  }

  /// A 40-point ballpoint stroke across the page at [y] (pt), ended in INK
  /// (pending until committed).
  ink.InkEdit drawStroke(double y) {
    ink.InkSample sample(double x) => ink.InkSample(
      position: Offset(x, y),
      timeUs: _timeUs += 4000,
      kind: ink.InkPointerKind.stylus,
      pressure: 0.5,
    );
    final stroke = controller.beginStroke(
      sample(40),
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      viewScale: 1.68,
    );
    for (var i = 1; i < 39; i++) {
      stroke.addSample(sample(40 + i * 12.0));
    }
    return stroke.end(sample(40 + 39 * 12.0))!;
  }

  void dispose() {
    mount.dispose();
    controller.dispose();
    unawaited(session.close());
    unawaited(store.close());
    async.flushMicrotasks();
  }
}

// ---- v2 fixtures ---------------------------------------------------------------

/// A laid-out viewport of [pages] on a 1032×1376 screen (the camera placed).
ViewportController _viewportOf(List<core.Page> pages) => ViewportController()
  ..updatePages(pages)
  ..updateViewportSize(const Size(1032, 1376))
  ..restore(null);

/// The shape drag's page.
const core.Page _page = core.Page(
  id: _pageId,
  noteId: _noteId,
  sortKey: 'a',
  size: core.PageSize.a4Portrait,
  background: core.BlankBackground(),
  createdAt: 0,
  updatedAt: 0,
  contentRevision: 0,
);

/// A short stroke of the clipboard set (page 'perf-src').
core.Stroke _stroke(int i) => lineStroke(
  id: 'perf-c$i',
  pageId: 'perf-src',
  x0: 20.0 + (i % 50) * 11,
  y0: 20.0 + (i ~/ 50) * 8,
  x1: 28.0 + (i % 50) * 11,
  y1: 24.0 + (i ~/ 50) * 8,
  pointCount: 12,
  createdAt: i,
);

/// Object [i] of a mixed set: rectangles, ellipses, pentagons, stars and
/// text boxes in a grid over the page (createdAt after the strokes).
core.PageObject _object(int i, {String pageId = 'perf-src'}) {
  final x = 20.0 + (i % 10) * 55;
  final y = 20.0 + (i ~/ 10) * 40;
  final rect = core.PageRect(x, y, x + 45, y + 30);
  final createdAt = 100000 + i;
  return switch (i % 5) {
    4 => PageObjectFixtures.textBox(
      pageId: pageId,
      id: 'perf-o$i',
      text: 'text $i',
      rect: rect,
      createdAt: createdAt,
    ),
    final k => PageObjectFixtures.shape(
      pageId: pageId,
      id: 'perf-o$i',
      kind: const [
        core.ShapeKind.rectangle,
        core.ShapeKind.ellipse,
        core.ShapeKind.polygon,
        core.ShapeKind.star,
      ][k],
      rect: rect,
      createdAt: createdAt,
    ),
  };
}
