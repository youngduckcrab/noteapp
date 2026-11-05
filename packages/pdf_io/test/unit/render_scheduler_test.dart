// The Dart render queue (06-pdf 6.7.3; 8 T8) under fake_async: priority classes (visible
// preview → visible tile → thumbnail → prefetch tile, request order within a class), at most
// two renders at a time, cancelling a queued job (leaves the queue, null at once) and a
// running one (token cancelled, a late image disposed), errors and the counters.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/render/render_scheduler.dart';
import 'package:pdf_io/src/render/tile_math.dart';

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(2, 2);
  picture.dispose();
  return image;
}

/// A render the test finishes by hand.
final class _Render {
  _Render(this.name);
  final String name;
  final Completer<ui.Image?> completer = Completer<ui.Image?>();
  PdfRenderCancelToken? token;
  bool started = false;

  Future<ui.Image?> call(PdfRenderCancelToken t) {
    started = true;
    token = t;
    return completer.future;
  }
}

void main() {
  test('at most two renders at a time; the rest wait in the queue', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler();
      final renders = [for (var i = 0; i < 4; i++) _Render('r$i')];
      for (final r in renders) {
        scheduler.submit(PdfRenderClass.visibleTile, r.call);
      }
      async.flushMicrotasks();
      expect(renders.map((r) => r.started), [true, true, false, false]);
      expect((scheduler.inflight, scheduler.queued), (2, 2));

      renders[0].completer.complete(_image());
      async.flushMicrotasks();
      expect(renders[2].started, isTrue);
      expect(renders[3].started, isFalse);
      expect((scheduler.inflight, scheduler.queued), (2, 1));
      expect(scheduler.rendered, 1);
    });
  });

  test('maxInflight is configurable', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler(maxInflight: 1);
      final a = _Render('a'), b = _Render('b');
      scheduler
        ..submit(PdfRenderClass.visibleTile, a.call)
        ..submit(PdfRenderClass.visibleTile, b.call);
      async.flushMicrotasks();
      expect((a.started, b.started), (true, false));
    });
  });

  test('priority: preview → visible tile → thumbnail → prefetch; FIFO inside a class', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler(maxInflight: 1);
      final order = <String>[];
      final blocker = _Render('blocker');
      scheduler.submit(PdfRenderClass.prefetchTile, blocker.call);
      async.flushMicrotasks();
      expect(blocker.started, isTrue);

      Future<ui.Image?> Function(PdfRenderCancelToken) record(String name) =>
          (token) async {
            order.add(name);
            return _image();
          };
      scheduler
        ..submit(PdfRenderClass.prefetchTile, record('prefetch1'))
        ..submit(PdfRenderClass.thumbnail, record('thumb1'))
        ..submit(PdfRenderClass.visibleTile, record('tile1'))
        ..submit(PdfRenderClass.visiblePreview, record('preview1'))
        ..submit(PdfRenderClass.visibleTile, record('tile2'))
        ..submit(PdfRenderClass.prefetchTile, record('prefetch2'))
        ..submit(PdfRenderClass.visiblePreview, record('preview2'));
      blocker.completer.complete(_image());
      async.flushMicrotasks();
      expect(order, [
        'preview1',
        'preview2',
        'tile1',
        'tile2',
        'thumb1',
        'prefetch1',
        'prefetch2',
      ]);
      expect(scheduler.rendered, 8);
      expect((scheduler.queued, scheduler.inflight), (0, 0));
    });
  });

  test('cancelling a queued job: out of the queue, result null at once', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler(maxInflight: 1);
      final a = _Render('a'), b = _Render('b'), c = _Render('c');
      scheduler.submit(PdfRenderClass.visibleTile, a.call);
      final jobB = scheduler.submit(PdfRenderClass.visibleTile, b.call);
      scheduler.submit(PdfRenderClass.visibleTile, c.call);
      ui.Image? result;
      var done = false;
      jobB.result.then((image) {
        result = image;
        done = true;
      });
      jobB.cancel();
      jobB.cancel(); // idempotent
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(result, isNull);
      expect(jobB.isCancelled, isTrue);
      expect(scheduler.queued, 1);
      expect(scheduler.cancelled, 1);

      a.completer.complete(_image());
      async.flushMicrotasks();
      expect(b.started, isFalse, reason: 'never rendered');
      expect(c.started, isTrue);
    });
  });

  test(
    'cancelling a running job cancels its token; a late image is disposed',
    () {
      fakeAsync((async) {
        final scheduler = PdfRenderScheduler();
        final a = _Render('a');
        final job = scheduler.submit(PdfRenderClass.visibleTile, a.call);
        async.flushMicrotasks();
        expect(a.started, isTrue);
        Object? result = 'pending';
        job.result.then((image) => result = image);

        job.cancel();
        expect(a.token!.isCancelled, isTrue);
        expect(
          scheduler.inflight,
          1,
          reason: 'still running until the engine returns',
        );
        async.flushMicrotasks();
        expect(result, 'pending');

        final late = _image();
        a.completer.complete(late);
        async.flushMicrotasks();
        expect(result, isNull);
        expect(late.debugDisposed, isTrue);
        expect(scheduler.inflight, 0);
        expect(scheduler.rendered, 0);
        expect(scheduler.cancelled, 1);
      });
    },
  );

  test('a running job whose engine throws after cancel ends with null', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler();
      final a = _Render('a');
      final job = scheduler.submit(PdfRenderClass.visibleTile, a.call);
      async.flushMicrotasks();
      Object? result = 'pending';
      job.result.then((image) => result = image);
      job.cancel();
      a.completer.completeError(StateError('aborted'));
      async.flushMicrotasks();
      expect(result, isNull);
    });
  });

  test('errors reach the result; the queue goes on', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler(maxInflight: 1);
      final failing = scheduler.submit(
        PdfRenderClass.visibleTile,
        (_) => throw const PdfIoException(PdfErrorCode.corrupt),
      );
      final next = _Render('next');
      scheduler.submit(PdfRenderClass.visibleTile, next.call);
      Object? error;
      failing.result.catchError((Object e) {
        error = e;
        return null;
      });
      async.flushMicrotasks();
      expect(error, isA<PdfIoException>());
      expect(next.started, isTrue);
    });
  });

  test('null from the engine is not counted as rendered', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler();
      scheduler.submit(PdfRenderClass.visibleTile, (_) async => null);
      async.flushMicrotasks();
      expect(scheduler.rendered, 0);
      expect(scheduler.lastRenderMs, 0);
    });
  });

  test('render times: last and p95 over the recent renders', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler();
      for (var i = 0; i < 5; i++) {
        scheduler.submit(PdfRenderClass.visibleTile, (_) async => _image());
      }
      async.flushMicrotasks();
      expect(scheduler.rendered, 5);
      expect(scheduler.lastRenderMs, greaterThanOrEqualTo(0));
      expect(scheduler.p95RenderMs, greaterThanOrEqualTo(0));
    });
  });

  test('onChanged fires on submit, start / finish and cancel', () {
    fakeAsync((async) {
      var changes = 0;
      final scheduler = PdfRenderScheduler(onChanged: () => changes++);
      final a = _Render('a');
      final job = scheduler.submit(PdfRenderClass.visibleTile, a.call);
      expect(changes, 1);
      job.cancel();
      expect(changes, 2);
      a.completer.complete(null);
      async.flushMicrotasks();
      expect(changes, 3);
    });
  });

  test('dispose cancels everything; later submits are cancelled', () {
    fakeAsync((async) {
      final scheduler = PdfRenderScheduler(maxInflight: 1);
      final a = _Render('a'), b = _Render('b');
      final jobA = scheduler.submit(PdfRenderClass.visibleTile, a.call);
      final jobB = scheduler.submit(PdfRenderClass.visibleTile, b.call);
      async.flushMicrotasks();
      scheduler.dispose();
      expect(a.token!.isCancelled, isTrue);
      expect(jobB.isCancelled, isTrue);
      final c = _Render('c');
      final jobC = scheduler.submit(PdfRenderClass.visibleTile, c.call);
      Object? resultC = 'pending';
      jobC.result.then((image) => resultC = image);
      async.flushMicrotasks();
      expect(resultC, isNull);
      expect(c.started, isFalse);
      expect(jobA.isCancelled, isTrue);
    });
  });
}
