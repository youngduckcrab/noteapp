// E-01: the test helpers work (04-editor 8.2 E-01, 9.1).
// - pumpEditor opens a 3-page A4 note and returns EditorTestHandles;
// - PointerDriver's pressure / tilt / radius / timestamps reach a Listener
//   unchanged, and its clock moves with fake time;
// - RecordingNoteSession records calls in order and flags an execute made
//   while one of its streams delivers;
// - after rejectNext(error), the next execute / undo does not reach CORE and
//   throws that error.
import 'dart:async';

import 'package:feature_editor/src/input/input_sample.dart';
import 'package:feature_editor/src/input/input_targets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pointer_driver.dart';
import '../helpers/pump_editor.dart';
import '../helpers/recording_input_targets.dart';
import '../helpers/recording_note_session.dart';
import '../helpers/test_data.dart';

/// A full-screen Listener that records every pointer event it receives.
Future<List<PointerEvent>> _pumpListener(WidgetTester tester) async {
  final events = <PointerEvent>[];
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: events.add,
        onPointerMove: events.add,
        onPointerUp: events.add,
        onPointerCancel: events.add,
        onPointerHover: events.add,
        onPointerSignal: events.add,
        child: const SizedBox.expand(),
      ),
    ),
  );
  return events;
}

Future<(core.NoteStore, RecordingNoteSession, core.PageId)> _openRecorded({
  List<core.Stroke> strokes = const [],
}) async {
  final store = createFakeNoteStore();
  final note = await store.library.createNote(title: 'r');
  final recorder = RecordingNoteSession(await store.openSession(note.id));
  final pageId = recorder.pages.first.id;
  await recorder.openPage(pageId);
  if (strokes.isNotEmpty) {
    recorder.execute(
      core.AddStrokes(
        pageId: pageId,
        strokes: [for (final s in strokes) s.copyWith(pageId: pageId)],
      ),
    );
  }
  return (store, recorder, pageId);
}

Future<void> _closeRecorded(
  core.NoteStore store,
  RecordingNoteSession recorder,
) async {
  await recorder.close();
  await store.close();
}

void main() {
  group('pumpEditor', () {
    testWidgets('opens a 3-page A4 note and returns the handles', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        title: '도구 확인',
        strokesByPageIndex: {
          0: [strokeA, strokeB],
        },
      );

      expect(
        tester.view.physicalSize / tester.view.devicePixelRatio,
        const Size(1032, 1376),
      );
      expect(find.text('도구 확인'), findsOneWidget);

      final session = h.session;
      expect(session.noteId, h.noteId);
      expect(session.pages, hasLength(3));
      expect(
        [for (final p in session.pages) p.id],
        [h.pageId(0), h.pageId(1), h.pageId(2)],
      );
      for (final p in session.pages) {
        expect(p.size, core.PageSize.a4Portrait);
        expect(p.background, const core.BlankBackground());
      }
      expect(session.history.undoDepth, 0, reason: 'seeding is not undoable');

      final recorder = h.recorder;
      expect(recorder, isNotNull);
      expect(recorder!.inner, same(session));
      expect(
        h.container.read(core.noteSessionProvider(h.noteId)).value,
        same(recorder),
        reason: 'the screen reads the recording session',
      );

      final content = await session.openPage(h.pageId(0));
      expect(content.strokeById(strokeA.id)!.pageId, h.pageId(0));
      expect(content.strokeById(strokeB.id), isNotNull);
      session.closePage(h.pageId(0));
      expect(h.driver.tester, same(tester));
    });

    testWidgets('recordSession: false uses CORE\'s own provider', (
      tester,
    ) async {
      final h = await pumpEditor(tester, pages: 1, recordSession: false);
      expect(h.recorder, isNull);
      expect(h.session.pages, hasLength(1));
      expect(h.session, isNot(isA<RecordingNoteSession>()));
    });

    testWidgets('a landscape size and onClose are passed through', (
      tester,
    ) async {
      var closed = 0;
      final h = await pumpEditor(
        tester,
        logicalSize: const Size(1376, 1032),
        onClose: () => closed++,
      );
      expect(tester.view.physicalSize, const Size(2752, 2064));
      await tester.tap(find.bySemanticsLabel('뒤로'));
      await tester.pump();
      expect(closed, 1);
      expect(h.closeCount, 1);
      expect(h.recorder!.calls, contains('flush'));
    });
  });

  group('PointerDriver', () {
    testWidgets(
      'pressure, tilt, radius, kind and timestamps arrive unchanged',
      (tester) async {
        final events = await _pumpListener(tester);
        final d = PointerDriver(tester);
        final t0 = d.now;

        await d.down(
          1,
          const Offset(100, 200),
          kind: PointerDeviceKind.stylus,
          pressure: 0.7,
          tilt: 0.4,
          radiusMajor: 12,
        );
        await d.wait(const Duration(milliseconds: 16));
        await d.move(1, const Offset(110, 205), pressure: 0.3);
        await d.wait(const Duration(milliseconds: 16));
        await d.up(1);

        expect(events, [
          isA<PointerDownEvent>(),
          isA<PointerMoveEvent>(),
          isA<PointerUpEvent>(),
        ]);
        final [down, move, up] = events;
        expect(down.kind, PointerDeviceKind.stylus);
        expect(down.pressure, 0.7);
        expect(down.tilt, 0.4);
        expect(down.radiusMajor, 12);
        expect(down.position, const Offset(100, 200));
        expect(down.timeStamp, t0);
        expect(move.pressure, 0.3);
        expect(move.tilt, 0.4);
        expect(move.radiusMajor, 12);
        expect(move.delta, const Offset(10, 5));
        expect(move.timeStamp, t0 + const Duration(milliseconds: 16));
        expect(up.timeStamp, t0 + const Duration(milliseconds: 32));
        expect(d.now, t0 + const Duration(milliseconds: 32));
        expect(down.pointer, move.pointer);
        expect(down.device, 1);

        // The adapter INK tools use sees the same raw values (no EDITOR
        // normalization — 6.5.5).
        final sample = InputSample.fromEvent(down);
        expect(sample.radiusMajor, 12);
        expect(sample.timeStamp, t0);
      },
    );

    testWidgets('wait() advances fake time with the event clock', (
      tester,
    ) async {
      await _pumpListener(tester);
      final d = PointerDriver(tester);
      var fired = false;
      Timer(const Duration(milliseconds: 500), () => fired = true);
      await d.wait(const Duration(milliseconds: 499));
      expect(fired, isFalse);
      await d.wait(const Duration(milliseconds: 1));
      expect(fired, isTrue);
    });

    testWidgets('composite gestures send the expected event sequences', (
      tester,
    ) async {
      final events = await _pumpListener(tester);
      final d = PointerDriver(tester);

      await d.stylusStroke(
        const [Offset(10, 10), Offset(20, 10), Offset(30, 10)],
        pressures: const [0.2, 0.5, 0.9],
        tilt: 0.3,
      );
      expect(events, [
        isA<PointerDownEvent>(),
        isA<PointerMoveEvent>(),
        isA<PointerMoveEvent>(),
        isA<PointerUpEvent>(),
      ]);
      expect([for (final e in events.take(3)) e.pressure], [0.2, 0.5, 0.9]);
      expect(events.every((e) => e.kind == PointerDeviceKind.stylus), isTrue);
      expect(
        events[1].timeStamp - events[0].timeStamp,
        const Duration(milliseconds: 4),
      );
      events.clear();

      await d.fingerDrag(Offset.zero, const Offset(100, 0), steps: 4);
      expect(events.whereType<PointerMoveEvent>(), hasLength(4));
      expect(events.last.position, const Offset(100, 0));
      expect(events.every((e) => e.kind == PointerDeviceKind.touch), isTrue);
      events.clear();

      await d.multiTap(const [Offset(10, 10), Offset(60, 10)]);
      expect(events.whereType<PointerDownEvent>(), hasLength(2));
      expect(events.whereType<PointerUpEvent>(), hasLength(2));
      expect(
        events.last.timeStamp - events.first.timeStamp,
        const Duration(milliseconds: 100),
      );
      events.clear();

      await d.pinch(
        center: const Offset(300, 300),
        startSpan: 100,
        endSpan: 200,
        steps: 2,
      );
      final downs = events.whereType<PointerDownEvent>().toList();
      expect(downs, hasLength(2));
      expect((downs[0].position - downs[1].position).distance, 100);
      final lastMoves = events.whereType<PointerMoveEvent>().toList();
      expect(
        (lastMoves[lastMoves.length - 1].position -
                lastMoves[lastMoves.length - 2].position)
            .distance,
        200,
      );
      events.clear();

      await d.hover(const Offset(5, 5));
      await d.wheel(const Offset(5, 5), const Offset(0, 100));
      expect(events, [isA<PointerHoverEvent>(), isA<PointerScrollEvent>()]);
      expect(events[0].kind, PointerDeviceKind.stylus);
      expect(
        (events[1] as PointerScrollEvent).scrollDelta,
        const Offset(0, 100),
      );
    });

    testWidgets('every down gets a fresh event pointer', (tester) async {
      final events = await _pumpListener(tester);
      final d = PointerDriver(tester);
      await d.down(1, const Offset(1, 1));
      await d.up(1);
      await d.down(1, const Offset(1, 1));
      await d.cancel(1);
      expect(events[0].pointer, isNot(events[2].pointer));
      expect(events[3], isA<PointerCancelEvent>());
      expect(() => d.up(1), throwsStateError);
    });
  });

  group('RecordingNoteSession', () {
    test('records calls in order', () async {
      final (store, recorder, pageId) = await _openRecorded();
      recorder.execute(
        core.AddStrokes(
          pageId: pageId,
          strokes: [strokeA.copyWith(pageId: pageId)],
        ),
      );
      await recorder.undo();
      await recorder.redo();
      await recorder.executeAsync(core.ClearPage(pageId: pageId));
      recorder.closePage(pageId);
      await recorder.flush();
      expect(recorder.calls, [
        'openPage:$pageId',
        'execute:add-strokes',
        'undo',
        'redo',
        'executeAsync:clear-page',
        'closePage:$pageId',
        'flush',
      ]);
      expect(recorder.executeDuringDelivery, isFalse);
      await _closeRecorded(store, recorder);
    });

    test('flags an execute made while a stream delivers', () async {
      final (store, recorder, pageId) = await _openRecorded();
      Object? reentryError;
      var sawDelivering = false;
      final sub = recorder.pageChanges(pageId).listen((change) {
        if (change.origin != core.ChangeOrigin.local) return;
        sawDelivering = recorder.isDelivering;
        try {
          recorder.execute(core.ClearPage(pageId: pageId));
        } on Object catch (e) {
          reentryError = e;
        }
      });
      // A listener that does nothing must not set the flag.
      final quiet = recorder.historyStream.listen((_) {});
      recorder.execute(
        core.AddStrokes(
          pageId: pageId,
          strokes: [strokeA.copyWith(pageId: pageId)],
        ),
      );
      expect(sawDelivering, isTrue);
      expect(recorder.executeDuringDelivery, isTrue);
      expect(reentryError, isA<StateError>(), reason: 'N-2 v1.1 in CORE');
      await sub.cancel();
      await quiet.cancel();
      await _closeRecorded(store, recorder);
    });

    test('a quiet listener leaves the flag false', () async {
      final (store, recorder, pageId) = await _openRecorded();
      final seen = <core.PageContentChange>[];
      final sub = recorder.pageChanges(pageId).listen(seen.add);
      recorder.execute(
        core.AddStrokes(
          pageId: pageId,
          strokes: [strokeA.copyWith(pageId: pageId)],
        ),
      );
      // Deferred work after delivery is fine (N-2: scheduleMicrotask).
      await Future<void>.delayed(Duration.zero);
      recorder.execute(core.ClearPage(pageId: pageId));
      expect(
        seen.where((c) => c.origin == core.ChangeOrigin.local),
        hasLength(2),
      );
      expect(recorder.executeDuringDelivery, isFalse);
      expect(recorder.isDelivering, isFalse);
      await sub.cancel();
      await _closeRecorded(store, recorder);
    });

    test('rejectNext: the next execute throws without reaching CORE', () async {
      final (store, recorder, pageId) = await _openRecorded();
      const race = core.ReadOnlyNoteException('race');
      recorder.rejectNext(race);
      final add = core.AddStrokes(
        pageId: pageId,
        strokes: [strokeA.copyWith(pageId: pageId)],
      );
      expect(() => recorder.execute(add), throwsA(same(race)));
      expect(recorder.inner.history.undoDepth, 0);
      expect(recorder.pageIfLoaded(pageId)!.strokeById(strokeA.id), isNull);
      expect(recorder.calls.last, 'execute:add-strokes:rejected');

      // Only one call is rejected.
      recorder.execute(add);
      expect(recorder.inner.history.undoDepth, 1);
      expect(recorder.calls.last, 'execute:add-strokes');
      await _closeRecorded(store, recorder);
    });

    test(
      'rejectNext: the next undo fails with the error, history kept',
      () async {
        final (store, recorder, pageId) = await _openRecorded(
          strokes: [strokeA],
        );
        expect(recorder.history.undoDepth, 1);
        final error = StateError('injected');
        recorder.rejectNext(error);
        await expectLater(recorder.undo(), throwsA(same(error)));
        expect(recorder.history.undoDepth, 1, reason: 'CORE was not reached');
        expect(
          recorder.pageIfLoaded(pageId)!.strokeById(strokeA.id),
          isNotNull,
        );
        expect(recorder.calls.last, 'undo:rejected');

        final result = await recorder.undo();
        expect(result.applied, isTrue);
        expect(recorder.history.undoDepth, 0);

        recorder.rejectNext(error);
        await expectLater(
          recorder.executeAsync(core.ClearPage(pageId: pageId)),
          throwsA(same(error)),
        );
        expect(recorder.calls.last, 'executeAsync:clear-page:rejected');
        await _closeRecorded(store, recorder);
      },
    );
  });

  group('RecordingInputTargets', () {
    test('records calls and hands out recording interactions', () {
      final targets = RecordingInputTargets();
      final down = InputSample.fromEvent(
        const PointerDownEvent(
          kind: PointerDeviceKind.stylus,
          position: Offset(1, 1),
        ),
      );
      final i =
          targets.beginInteraction(down, source: InteractionSource.stylus)!
              as RecordingToolInteraction;
      i.move(
        InputSample.fromEvent(
          const PointerMoveEvent(
            kind: PointerDeviceKind.stylus,
            position: Offset(4, 5),
          ),
        ),
      );
      i.end(down);
      targets.tapGesture(2, Offset.zero);
      targets.refuseInteractions = true;
      expect(
        targets.beginInteraction(down, source: InteractionSource.finger),
        isNull,
      );
      expect(targets.calls, ['begin(stylus)', 'tap(2)', 'begin(finger)']);
      expect(i.travelled, 5);
      expect(i.isEnded, isTrue);
      expect(targets.policy.penOnly, isFalse);
    });
  });
}
