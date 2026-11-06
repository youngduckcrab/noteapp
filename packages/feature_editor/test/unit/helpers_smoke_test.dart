// E-01: the test helpers work (04-editor 8.2 E-01, 9.1).
// - pumpEditor opens a 3-page A4 note and returns EditorTestHandles;
// - PointerDriver's pressure / tilt / radius / timestamps reach a Listener
//   unchanged, and its clock moves with fake time;
// - RecordingNoteSession records calls in order and flags an execute made
//   while one of its streams delivers;
// - after rejectNext(error), the next execute / undo does not reach CORE and
//   throws that error.
// (v2, m5-7/04-editor 8.2 E2-00) the new helpers:
// - PointerDriver: a pen-button down (0x02) reaches a Listener unchanged, the
//   web order down 0x02 → move 0x03 → move 0x02 → up, the eraser tip;
// - pumpEditor seeds page objects and recordings and overrides the fake
//   audio ports, the image slot, the Pencil source and the extensions;
// - FakeImageImporter puts an asset into the fake store and returns an
//   ImportedImage (onPick runs inside the call; cancel, sync / async errors);
// - FakeStylusExtras injects Pencil events;
// - the test extension items, ink_edit_builders and the mapping table.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/input_sample.dart';
import 'package:feature_editor/src/input/input_targets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/fake_extensions.dart';
import '../helpers/fake_image_importer.dart';
import '../helpers/fake_stylus_extras.dart';
import '../helpers/ink_edit_builders.dart';
import '../helpers/mapping_table.dart';
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
  group('v2 helpers (E2-00)', () {
    testWidgets('a pen-button down (0x02) reaches the Listener unchanged', (
      tester,
    ) async {
      final events = await _pumpListener(tester);
      final d = PointerDriver(tester);
      await d.nativePenButtonStroke(const [Offset(100, 100), Offset(120, 110)]);

      expect(events, [
        isA<PointerDownEvent>(),
        isA<PointerMoveEvent>(),
        isA<PointerUpEvent>(),
      ]);
      expect(events.first.buttons, kPrimaryStylusButton);
      expect(events.first.buttons, 0x02);
      expect(events.first.kind, PointerDeviceKind.stylus);
      expect(events[1].buttons, 0x02);
    });

    testWidgets('the web order down 0x02 → move 0x03 → move 0x02 → up', (
      tester,
    ) async {
      final events = await _pumpListener(tester);
      final d = PointerDriver(tester);
      await d.webPenButtonStroke(const [
        Offset(100, 100),
        Offset(110, 100),
        Offset(120, 100),
      ]);

      String typeOf(PointerEvent e) => switch (e) {
        PointerDownEvent() => 'down',
        PointerMoveEvent() => 'move',
        PointerUpEvent() => 'up',
        _ => e.runtimeType.toString(),
      };
      expect(
        [for (final e in events) (typeOf(e), e.buttons)],
        [
          ('down', 0x02),
          ('move', 0x03),
          ('move', 0x03),
          ('move', 0x02),
          ('up', 0),
        ],
      );
      expect(events.every((e) => e.kind == PointerDeviceKind.stylus), isTrue);
      expect(events.map((e) => e.pointer).toSet(), hasLength(1));
      expect(events[3].position, const Offset(120, 100));
      expect(
        () => d.webPenButtonStroke(const [Offset(1, 1)]),
        throwsArgumentError,
      );
    });

    testWidgets('move(buttons:) and hover(buttons:) and the eraser tip', (
      tester,
    ) async {
      final events = await _pumpListener(tester);
      final d = PointerDriver(tester);
      await d.hover(const Offset(50, 50), buttons: 0x02);
      await d.eraserTipStroke(const [Offset(10, 10), Offset(20, 20)]);
      await d.down(
        3,
        const Offset(5, 5),
        kind: PointerDeviceKind.stylus,
        buttons: 0x02,
      );
      await d.move(3, const Offset(6, 6), buttons: 0x03);
      await d.move(3, const Offset(7, 7));
      await d.up(3);

      expect(events.first, isA<PointerHoverEvent>());
      expect(events.first.buttons, 0x02);
      final tip = events.whereType<PointerDownEvent>().first;
      expect(tip.kind, PointerDeviceKind.invertedStylus);
      final moves = events.whereType<PointerMoveEvent>().skip(1).toList();
      expect([for (final m in moves) m.buttons], [0x03, 0x03]);
    });

    testWidgets('pumpEditor seeds page objects and recordings', (tester) async {
      final shape = PageObjectFixtures.shape(
        pageId: 'elsewhere',
        id: 'shape-1',
      );
      final text = PageObjectFixtures.textBox(
        pageId: 'elsewhere',
        id: 'text-1',
      );
      final h = await pumpEditor(
        tester,
        objectsByPageIndex: {
          1: [shape, text],
        },
        strokesByPageIndex: {
          1: [strokeA.copyWith(recordingId: 'rec-1', recordingOffsetMs: 1200)],
        },
        recordings: const [
          RecordingSeed(id: 'rec-1', durationMs: 5000, title: '복구된 녹음'),
        ],
        fakeAudio: true,
      );

      expect(h.session.history.undoDepth, 0);
      final content = await h.session.openPage(h.pageId(1));
      expect(content.objectCount, 2);
      expect(content.objectById('shape-1'), isA<core.ShapeObject>());
      expect(content.objectById('shape-1')!.pageId, h.pageId(1));
      expect(content.objectById('text-1')!.createdAt, text.createdAt);
      expect(content.strokeById(strokeA.id)!.recordingId, 'rec-1');
      h.session.closePage(h.pageId(1));

      final recordings = await h.store.recordings.recordingsOf(h.noteId);
      expect(recordings, hasLength(1));
      expect(recordings.single.id, 'rec-1');
      expect(recordings.single.title, '복구된 녹음');
      expect(recordings.single.durationMs, 5000);
      final audio = await h.store.assets.getAsset(recordings.single.assetId);
      expect(audio!.type, core.AssetType.audio);

      expect(
        h.container.read(core.audioRecorderServiceProvider),
        same(h.audioRecorder),
      );
      expect(
        h.container.read(core.audioPlaybackServiceProvider),
        same(h.audioPlayback),
      );
    });

    testWidgets('pumpEditor overrides the image slot, Pencil and extensions', (
      tester,
    ) async {
      final pencil = FakeStylusExtras();
      final item = RecordingSelectionItem();
      final h = await pumpEditor(
        tester,
        pages: 1,
        imageImporter: (store) => FakeImageImporter(store: store),
        stylusExtras: pencil,
        extensions: EditorExtensions(selectionMenuItems: [item.item]),
      );
      expect(
        h.container.read(editorImageImporterProvider),
        same(h.imageImporter!.importer),
      );
      expect(h.imageImporter!.store, same(h.store));
      expect(h.container.read(stylusExtrasProvider), same(pencil));
      expect(h.stylusExtras, same(pencil));
      expect(h.container.read(editorExtensionsProvider).selectionMenuItems, [
        item.item,
      ]);
    });

    testWidgets('FakeImageImporter puts an asset and returns ImportedImage', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final fake = FakeImageImporter(
        store: store,
        sources: const {core.ImageImportSource.photos},
        pixelWidth: 640,
        pixelHeight: 480,
      );
      final seen = <int>[];
      fake.onPick = (call) => seen.add(call.index);

      final future = fake.importer.pick(context, core.ImageImportSource.photos);
      expect(seen, [0], reason: 'onPick runs inside the call');
      final image = await tester.runAsync(() => future);
      expect(image!.pixelWidth, 640);
      expect(image.pixelHeight, 480);
      expect(image.asset.type, core.AssetType.image);
      expect(
        await tester.runAsync(() => store.assets.hasBytes(image.asset.id)),
        isTrue,
      );
      expect(fake.putAssetIds, [image.asset.id]);
      expect(fake.calls.single.source, core.ImageImportSource.photos);
      expect(fake.calls.single.context, same(context));
      expect(fake.calls.single.contextMounted, isTrue);
      expect(fake.importer.sources, {core.ImageImportSource.photos});

      fake.cancelNext = true;
      expect(
        await tester.runAsync(
          () => fake.pick(context, core.ImageImportSource.photos),
        ),
        isNull,
      );

      fake.throwNext = StateError('picker failed');
      await expectLater(
        fake.pick(context, core.ImageImportSource.photos),
        throwsStateError,
      );
      fake
        ..throwNext = StateError('sync')
        ..throwSynchronously = true;
      expect(
        () => fake.pick(context, core.ImageImportSource.photos),
        throwsStateError,
      );
      expect(fake.calls, hasLength(4));
    });

    test('FakeStylusExtras injects Pencil events', () async {
      final pencil = FakeStylusExtras(
        capabilities: const StylusCapabilities(doubleTap: true),
      );
      expect(pencil.isSupported, isTrue);
      expect(pencil.capabilities.doubleTap, isTrue);
      expect(pencil.capabilities.squeeze, isFalse);
      expect(pencil.hasListener, isFalse);

      final got = <StylusExtraEvent>[];
      final sub = pencil.events.listen(got.add);
      expect(pencil.hasListener, isTrue);
      expect(pencil.listenCount, 1);
      pencil
        ..emit(const StylusDoubleTap())
        ..emit(
          const StylusSqueeze(
            phase: StylusSqueezePhase.ended,
            hoverPosition: Offset(3, 4),
          ),
        );
      await Future<void>.delayed(Duration.zero);
      expect(got, [
        const StylusDoubleTap(),
        const StylusSqueeze(
          phase: StylusSqueezePhase.ended,
          hoverPosition: Offset(3, 4),
        ),
      ]);
      await sub.cancel();
      expect(pencil.cancelCount, 1);
      expect(FakeStylusExtras(isSupported: false).isSupported, isFalse);
      await pencil.close();
    });

    testWidgets('test extension items record their calls and run one command', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final executed = <core.EditCommand>[];
      final shape = PageObjectFixtures.shape(pageId: 'p1');
      final selectionItem = RecordingSelectionItem(
        command: (sel) => core.RemoveElements(
          pageId: sel.pageId,
          elementIds: [for (final o in sel.objects) o.id],
        ),
        isVisible: (sel) => sel.objects.isNotEmpty,
      );
      final selection = EditorSelectionContext(
        noteId: 'n',
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        strokes: const [],
        objects: [shape],
        boundsPt: Rect.zero,
        execute: executed.add,
        clearSelection: () {},
      );
      expect(selectionItem.item.isVisible!(selection), isTrue);
      expect(selectionItem.visibleCalls, 1);
      await selectionItem.item.onSelected(context, selection);
      expect(selectionItem.calls.single.menu, same(selection));
      expect(executed.single, isA<core.RemoveElements>());
      expect(selectionItem.item, same(selectionItem.item));

      selectionItem.throwSync = StateError('sync');
      expect(
        () => selectionItem.item.onSelected(context, selection),
        throwsStateError,
      );

      final selected = <String>[];
      final insertItem = RecordingInsertItem(
        command: (insert) =>
            core.AddObjects(pageId: insert.pageId, objects: [shape]),
        selectAfter: shape.id,
      );
      await insertItem.item.onSelected(
        context,
        EditorInsertContext(
          noteId: 'n',
          pageId: 'p1',
          pageSize: core.PageSize.a4Portrait,
          visibleRectPt: const Rect.fromLTWH(0, 0, 100, 100),
          execute: executed.add,
          selectObject: selected.add,
        ),
      );
      expect(executed.last, isA<core.AddObjects>());
      expect(selected, [shape.id]);

      final panels = TestRecordingPanelBuilder();
      final on = ValueNotifier(true);
      addTearDown(on.dispose);
      var closed = 0;
      final panel = panels.builder(
        context,
        EditorPanelContext(
          noteId: 'n',
          tapToSeek: on,
          setTapToSeek: (v) => on.value = v,
          close: () => closed++,
        ),
      );
      expect(panel, isA<TestRecordingPanel>());
      expect(panels.panelContexts, hasLength(1));
      panels.throwNext = StateError('build');
      expect(
        () => panels.builder(context, panels.panelContexts.single),
        throwsStateError,
      );
      expect(closed, 0);
    });

    test('addShapeEdit commits as one AddObjects', () {
      final shape = PageObjectFixtures.shape(pageId: 'p1');
      final edit = addShapeEdit('p1', shape);
      final command = edit.toCommand();
      expect(command, isA<core.AddObjects>());
      command as core.AddObjects;
      expect(command.pageId, 'p1');
      expect(command.objects, [shape]);
      final erase = eraseStrokesEdit('p1', objectIds: {shape.id}).toCommand();
      expect(erase, isA<core.RemoveElements>());
    });

    test('the mapping table rows are covered by P-A test files', () {
      expect(kEditorCommandMapping, isNotEmpty);
      for (final row in kEditorCommandMapping) {
        expect(kNotPaTasks, isNot(contains(row.task)), reason: row.action);
        expect(
          row.coveredBy.startsWith('widget/') ||
              row.coveredBy.startsWith('unit/'),
          isTrue,
          reason: row.coveredBy,
        );
        expect(row.coveredBy, endsWith('_test.dart'));
      }
      final autoShape = kEditorCommandMapping.singleWhere(
        (r) => r.action == '자동 도형 보정 확정',
      );
      expect(autoShape.coveredBy, 'widget/shape_tool_test.dart');
      expect(autoShape.task, 'E2-09');
    });
  });
}
