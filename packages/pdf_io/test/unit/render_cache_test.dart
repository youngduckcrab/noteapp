// The render cache (06-pdf 6.7.4, contract 7.4.10; 8 T8): web budgets, a byte budget per kind
// with LRU eviction of unused images, in-use images never removed (overBudgetBytes instead),
// the 30-second TTL of unused tiles (fake_async), trimMemory, the trim when the app is hidden
// (AppLifecycleListener registered by PdfRenderService itself) and statsListenable notifying
// only when the statistics change (PdfRenderStats ==).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/render/render_cache.dart';
import 'package:pdf_io/src/render/tile_math.dart';
import 'package:pdf_io/testing.dart';

const int _mib = 1024 * 1024;

/// 512 × 512 × 4 bytes = 1 MiB.
ui.Image _mibImage() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF336699), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(512, 512);
  picture.dispose();
  return image;
}

PdfRenderKey _key(PdfRenderKind kind, int i) => (
  assetId: 'a',
  pageIndex: i,
  kind: kind,
  scale: 1.0,
  tileX: 0,
  tileY: 0,
  backgroundArgb: 0xFFFFFFFF,
);

const PdfRenderBudget _small = PdfRenderBudget(
  previewBytes: 2 * _mib,
  tileBytes: 2 * _mib,
  thumbnailBytes: _mib,
);

void main() {
  test('web budgets: 32 / 64 / 16 MiB, 112 MiB in all (contract 7.4.10)', () {
    const web = PdfRenderBudget.web();
    expect(web.previewBytes, 32 * _mib);
    expect(web.tileBytes, 64 * _mib);
    expect(web.thumbnailBytes, 16 * _mib);
    expect(web.totalBytes, 112 * _mib);
    const native = PdfRenderBudget.native();
    expect(
      (native.previewBytes, native.tileBytes, native.thumbnailBytes),
      (64 * _mib, 160 * _mib, 32 * _mib),
    );
  });

  group('PdfRenderCache', () {
    test('bytes = width × height × 4, counted per kind', () {
      final cache = PdfRenderCache(budget: _small);
      final lease = cache.put(_key(PdfRenderKind.preview, 0), _mibImage());
      expect(cache.bytesOf(PdfRenderKind.preview), _mib);
      expect(cache.bytesOf(PdfRenderKind.tile), 0);
      expect(cache.liveImages, 1);
      expect(cache.refsOf(lease.key), 1);
      lease.release();
      lease.release(); // idempotent
      expect(cache.refsOf(lease.key), 0);
      expect(cache.liveImages, 1, reason: 'unused but within budget');
      cache.dispose();
    });

    test('over budget: unused images of that kind leave in LRU order', () {
      final cache = PdfRenderCache(budget: _small);
      final p0 = cache.put(_key(PdfRenderKind.preview, 0), _mibImage());
      final p1 = cache.put(_key(PdfRenderKind.preview, 1), _mibImage());
      final image0 = p0.image, image1 = p1.image;
      p0.release();
      p1.release();
      // Use p0 again: p1 becomes the least recently used.
      cache.take(_key(PdfRenderKind.preview, 0))!.release();
      final tile = cache.put(_key(PdfRenderKind.tile, 9), _mibImage());

      final p2 = cache.put(_key(PdfRenderKind.preview, 2), _mibImage());
      expect(cache.contains(_key(PdfRenderKind.preview, 1)), isFalse);
      expect(image1.debugDisposed, isTrue);
      expect(cache.contains(_key(PdfRenderKind.preview, 0)), isTrue);
      expect(image0.debugDisposed, isFalse);
      expect(cache.bytesOf(PdfRenderKind.preview), 2 * _mib);
      // Other kinds keep their own budget.
      expect(cache.contains(tile.key), isTrue);
      expect(cache.overBudgetBytes, 0);
      p2.release();
      tile.release();
      cache.dispose();
    });

    test('in-use images are never removed; the excess is overBudgetBytes', () {
      final cache = PdfRenderCache(budget: _small);
      final tiles = [
        for (var i = 0; i < 3; i++)
          cache.put(_key(PdfRenderKind.tile, i), _mibImage()),
      ];
      expect(cache.bytesOf(PdfRenderKind.tile), 3 * _mib);
      expect(cache.overBudgetBytes, _mib);
      expect(tiles.every((t) => !t.image.debugDisposed), isTrue);

      final last = tiles[2].image;
      tiles[2].release(); // unused and over budget → leaves at once
      expect(last.debugDisposed, isTrue);
      expect(cache.overBudgetBytes, 0);
      expect(cache.bytesOf(PdfRenderKind.tile), 2 * _mib);
      cache.dispose();
    });

    test('a second put of a cached key keeps the cached image', () {
      final cache = PdfRenderCache(budget: _small);
      final first = cache.put(_key(PdfRenderKind.preview, 0), _mibImage());
      final duplicate = _mibImage();
      final second = cache.put(_key(PdfRenderKind.preview, 0), duplicate);
      expect(duplicate.debugDisposed, isTrue);
      expect(identical(second.image, first.image), isTrue);
      expect(cache.refsOf(first.key), 2);
      expect(cache.bytesOf(PdfRenderKind.preview), _mib);
      cache.dispose();
    });

    test('release(dropIfUnused) removes the image at once (6.7.6)', () {
      final cache = PdfRenderCache(budget: _small);
      final a = cache.put(_key(PdfRenderKind.tile, 0), _mibImage());
      final b = cache.take(a.key)!;
      a.release(dropIfUnused: true);
      expect(cache.contains(a.key), isTrue, reason: 'b still uses it');
      final image = b.image;
      b.release(dropIfUnused: true);
      expect(cache.contains(a.key), isFalse);
      expect(image.debugDisposed, isTrue);
      cache.dispose();
    });

    test(
      'unused tiles leave 30 s after their last use (checked every 5 s)',
      () {
        fakeAsync((async) {
          final cache = PdfRenderCache(budget: const PdfRenderBudget.web());
          final tile = cache.put(_key(PdfRenderKind.tile, 0), _mibImage());
          final preview = cache.put(
            _key(PdfRenderKind.preview, 0),
            _mibImage(),
          );
          final tileImage = tile.image;
          async.elapse(const Duration(minutes: 2));
          expect(cache.contains(tile.key), isTrue, reason: 'in use');
          expect(async.periodicTimerCount, 0, reason: 'no idle tile, no timer');

          tile.release();
          preview.release();
          async.elapse(const Duration(seconds: 29));
          expect(cache.contains(tile.key), isTrue);
          async.elapse(const Duration(seconds: 7));
          expect(cache.contains(tile.key), isFalse);
          expect(tileImage.debugDisposed, isTrue);
          expect(
            cache.contains(preview.key),
            isTrue,
            reason: 'no TTL for previews',
          );
          expect(async.periodicTimerCount, 0);
          cache.dispose();
        });
      },
    );

    test('using a tile again restarts its 30 s', () {
      fakeAsync((async) {
        final cache = PdfRenderCache(budget: const PdfRenderBudget.web());
        cache.put(_key(PdfRenderKind.tile, 0), _mibImage()).release();
        async.elapse(const Duration(seconds: 20));
        cache.take(_key(PdfRenderKind.tile, 0))!.release();
        async.elapse(const Duration(seconds: 25));
        expect(cache.contains(_key(PdfRenderKind.tile, 0)), isTrue);
        async.elapse(const Duration(seconds: 15));
        expect(cache.contains(_key(PdfRenderKind.tile, 0)), isFalse);
        cache.dispose();
      });
    });

    test('trimMemory drops every unused image of every kind', () {
      var changes = 0;
      final cache = PdfRenderCache(
        budget: const PdfRenderBudget.web(),
        onChanged: () => changes++,
      );
      final used = cache.put(_key(PdfRenderKind.preview, 0), _mibImage());
      final unused = [
        for (final kind in PdfRenderKind.values)
          cache.put(_key(kind, 1), _mibImage()),
      ];
      final images = [for (final l in unused) l.image];
      for (final lease in unused) {
        lease.release();
      }
      expect(cache.liveImages, 4);
      final before = changes;
      cache.trimMemory();
      expect(changes, before + 1);
      expect(cache.liveImages, 1);
      expect(images.every((i) => i.debugDisposed), isTrue);
      expect(used.image.debugDisposed, isFalse);
      cache.trimMemory(); // nothing unused: no change
      expect(changes, before + 1);
      used.release();
      cache.dispose();
      expect(used.image.debugDisposed, isTrue);
    });
  });

  group('PdfRenderService', () {
    late FakePdfEngine engine;
    late FakePdfNoteGateway gateway;
    late DefaultPdfDocumentPool pool;
    late PdfRenderService service;

    const params = PdfBackgroundParams(
      assetId: 'asset-a',
      pdfPageIndex: 0,
      pageSize: Size(595.276, 841.89),
      deviceScale: 1,
    );

    setUp(() {
      engine = FakePdfEngine();
      gateway = FakePdfNoteGateway()
        ..arriveBytes(
          'asset-a',
          Uint8List.fromList('%PDF-1.7\n%%EOF\n'.codeUnits),
        );
      pool = DefaultPdfDocumentPool(engine: engine, gateway: gateway);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    testWidgets(
      'app hidden → unused images are trimmed (AppLifecycleListener)',
      (tester) async {
        service = PdfRenderService(
          pool: pool,
          budget: const PdfRenderBudget.web(),
        );
        final handle = service.attach(params);
        await settle(tester);
        expect(handle.snapshot.status, PdfRenderStatus.ready);
        expect(service.stats.previewBytes, greaterThan(0));
        handle.dispose(); // the preview stays in the LRU (6.7.6)
        await settle(tester);
        expect(service.stats.previewBytes, greaterThan(0));

        final binding = tester.binding;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        expect(service.stats.previewBytes, 0);
        expect(service.stats.liveImages, 0);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await service.dispose();
        await pool.dispose();
      },
    );

    testWidgets('trimOnAppHidden: false registers no listener', (tester) async {
      service = PdfRenderService(
        pool: pool,
        budget: const PdfRenderBudget.web(),
        trimOnAppHidden: false,
      );
      final handle = service.attach(params);
      await settle(tester);
      handle.dispose();
      await settle(tester);
      final bytes = service.stats.previewBytes;
      expect(bytes, greaterThan(0));
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(service.stats.previewBytes, bytes);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await service.dispose();
      await pool.dispose();
    });

    testWidgets('statsListenable notifies only when the statistics change', (
      tester,
    ) async {
      service = PdfRenderService(
        pool: pool,
        budget: const PdfRenderBudget.web(),
        trimOnAppHidden: false,
      );
      final stats = service.statsListenable;
      expect(stats.value, PdfRenderStats.zero);
      var calls = 0;
      void listener() => calls++;
      stats.addListener(listener);

      service.trimMemory(); // empty cache: nothing changes
      await settle(tester);
      expect(calls, 0);

      final handle = service.attach(params);
      await settle(tester);
      expect(calls, greaterThan(0));
      expect(stats.value.rendered, 1);
      expect(stats.value.liveImages, 1);
      expect(stats.value.openDocuments, 1);
      expect(stats.value, service.stats);

      final settled = calls;
      service.trimMemory(); // the preview is in use: nothing changes
      handle.update(params); // same params: nothing happens
      await settle(tester);
      expect(calls, settled);

      // Several changes in one go reach listeners as one update.
      handle.dispose();
      service.trimMemory();
      await settle(tester);
      expect(calls, settled + 1);
      expect(stats.value.liveImages, 0);
      stats.removeListener(listener);
      await service.dispose();
      await pool.dispose();
    });
  });
}
