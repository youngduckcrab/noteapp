// PDF T25a — ExportMemoryLedger and the JPEG cache (m5-7/06-pdf 6.2.10, 수정 2회차·3회차):
// hold · release · makeRoom sums, peaks, overBudget, the copy kind outside the budget, LRU.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/tuning.dart';

const int mib = 1024 * 1024;

void main() {
  group('ExportMemoryLedger', () {
    test('default budget = exportImageTempBytes (16 MiB)', () {
      expect(ExportMemoryLedger().budgetBytes, 16 * mib);
      expect(PdfTuning.exportImageTempBytes, 16 * mib);
    });

    test('hold / release: sums by kind, peaks, count', () {
      final l = ExportMemoryLedger();
      final a = l.hold(ExportMemoryKind.rgba, 4 * mib);
      final b = l.hold(ExportMemoryKind.encoded, 3 * mib);
      expect(l.heldBytes, 7 * mib);
      expect(l.bytesOf(ExportMemoryKind.rgba), 4 * mib);
      expect(l.bytesOf(ExportMemoryKind.encoded), 3 * mib);
      expect(l.heldCount, 2);
      l.release(a);
      expect(l.heldBytes, 3 * mib);
      l.release(a); // idempotent
      expect(l.heldBytes, 3 * mib);
      expect(a.isReleased, isTrue);
      final c = l.hold(ExportMemoryKind.rgba, 1 * mib);
      expect(l.peakBytes, 7 * mib);
      expect(l.peakCount, 2);
      l
        ..release(b)
        ..release(c);
      expect((l.heldBytes, l.heldCount), (0, 0));
      expect(l.overBudget, 0);
      expect(() => l.hold(ExportMemoryKind.rgba, -1), throwsArgumentError);
    });

    test(
      'overBudget counts each time the sum goes over, not every hold above',
      () {
        final l = ExportMemoryLedger();
        final input = l.hold(ExportMemoryKind.encoded, 20 * mib);
        expect(l.overBudget, 1);
        final out = l.hold(ExportMemoryKind.rgba, 4 * mib);
        expect(l.overBudget, 1, reason: 'still over: the same episode');
        expect(l.peakBytes, 24 * mib);
        l
          ..release(input)
          ..release(out);
        final exact = l.hold(ExportMemoryKind.rgba, 16 * mib);
        expect(l.overBudget, 1, reason: '= budget is inside');
        final one = l.hold(ExportMemoryKind.encoded, 1);
        expect(l.overBudget, 2);
        l
          ..release(exact)
          ..release(one);
      },
    );

    test('copy is outside the budget: peakCopyBytes / peakTotalBytes only', () {
      final l = ExportMemoryLedger();
      final rgba = l.hold(ExportMemoryKind.rgba, 16 * mib);
      final copy = l.holdCopy(16 * mib);
      expect(l.heldBytes, 16 * mib);
      expect(l.copyBytes, 16 * mib);
      expect(l.peakBytes, 16 * mib);
      expect(l.peakCopyBytes, 16 * mib);
      expect(l.peakTotalBytes, 32 * mib);
      expect(l.overBudget, 0);
      expect(l.heldCount, 1, reason: 'copy is not a budget handle');
      l
        ..release(copy)
        ..release(rgba);
      expect((l.heldBytes, l.copyBytes), (0, 0));
      expect(l.peakTotalBytes, 32 * mib);
    });

    test('makeRoom evicts cache entries oldest first, only as needed', () {
      final l = ExportMemoryLedger();
      final cache = ExportJpegCache(l);
      expect(cache.offer('a', _bytes(5 * mib)), isTrue);
      expect(cache.offer('b', _bytes(5 * mib)), isTrue);
      expect(cache.offer('c', _bytes(5 * mib)), isTrue);
      expect(l.bytesOf(ExportMemoryKind.cache), 15 * mib);
      l.makeRoom(2 * mib); // 15 + 2 > 16 → drop 'a'
      expect(cache.assetIds, ['b', 'c']);
      final rgba = l.hold(ExportMemoryKind.rgba, 7 * mib); // 10 + 7 > 16 → 'b'
      expect(cache.assetIds, ['c']);
      expect(l.heldBytes, 12 * mib);
      expect(l.peakBytes, 15 * mib);
      l.release(rgba);
      final big = l.hold(
        ExportMemoryKind.rgba,
        16 * mib,
      ); // the cache goes to 0
      expect(cache.length, 0);
      expect(l.heldBytes, 16 * mib);
      expect(l.overBudget, 0);
      l.release(big);
    });

    test('one cache per ledger', () {
      final l = ExportMemoryLedger();
      ExportJpegCache(l);
      expect(() => ExportJpegCache(l), throwsStateError);
    });
  });

  group('ExportJpegCache', () {
    test('take moves an entry out (its cache bytes released)', () {
      final l = ExportMemoryLedger();
      final cache = ExportJpegCache(l);
      final bytes = _bytes(6 * mib);
      cache.offer('a', bytes);
      final taken = cache.take('a');
      expect(identical(taken, bytes), isTrue);
      expect(l.heldBytes, 0);
      expect(cache.take('a'), isNull);
      expect(cache.take('unknown'), isNull);
    });

    test(
      'offer: newest kept, older evicted; too big for the room → dropped',
      () {
        final l = ExportMemoryLedger();
        final cache = ExportJpegCache(l);
        final held = l.hold(ExportMemoryKind.rgba, 8 * mib);
        expect(cache.offer('a', _bytes(5 * mib)), isTrue);
        expect(cache.offer('b', _bytes(5 * mib)), isTrue); // 'a' goes
        expect(cache.assetIds, ['b']);
        expect(
          cache.offer('c', _bytes(9 * mib)),
          isFalse,
          reason: '8 + 9 > 16',
        );
        expect(cache.assetIds, [
          'b',
        ], reason: 'a failed offer keeps the others');
        expect(l.heldBytes, 13 * mib);
        // offering the same id again replaces it as the newest
        expect(cache.offer('d', _bytes(1 * mib)), isTrue);
        expect(cache.offer('b', _bytes(2 * mib)), isTrue);
        expect(cache.assetIds, ['d', 'b']);
        expect(l.bytesOf(ExportMemoryKind.cache), 3 * mib);
        cache.clear();
        expect((cache.length, l.bytesOf(ExportMemoryKind.cache)), (0, 0));
        l.release(held);
        expect(l.peakBytes, lessThanOrEqualTo(16 * mib));
      },
    );
  });
}

Uint8List _bytes(int n) => Uint8List(n);
