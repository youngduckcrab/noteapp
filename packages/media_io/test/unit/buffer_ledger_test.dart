// Buffer ledger (m5-7/06-pdf 6.6.5; 8.2 T31a — M-4, C22-05): hold / swap / release and the
// peaks the stop and recovery tests read (peakCount ≤ 2 — the header patch holds two buffers
// only for the copy).
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/record/buffer_ledger.dart';

void main() {
  test('the stop path: readAll → patch (swap) → put → release', () {
    final ledger = BufferLedger();
    final read = ledger.hold(1000);
    expect((ledger.count, ledger.bytes), (1, 1000));
    final patched = ledger.swap(read, 1011); // head + rest, copied once
    expect((ledger.count, ledger.bytes), (1, 1011));
    expect(ledger.peakCount, 2);
    expect(ledger.peakBytes, 2011);
    ledger.release(patched);
    expect((ledger.count, ledger.bytes), (0, 0));
    expect(ledger.peakCount, 2);
  });

  test('release twice is a no-op; peaks keep the maximum', () {
    final ledger = BufferLedger();
    final a = ledger.hold(10);
    final b = ledger.hold(20);
    final c = ledger.hold(30);
    expect(ledger.peakCount, 3);
    expect(ledger.peakBytes, 60);
    ledger
      ..release(b)
      ..release(b);
    expect((ledger.count, ledger.bytes), (2, 40));
    ledger
      ..release(a)
      ..release(c);
    expect((ledger.count, ledger.bytes), (0, 0));
    expect((ledger.peakCount, ledger.peakBytes), (3, 60));
  });

  test('resetPeaks starts from what is held now', () {
    final ledger = BufferLedger();
    final a = ledger.hold(5);
    ledger.release(ledger.hold(7));
    ledger.resetPeaks();
    expect((ledger.peakCount, ledger.peakBytes), (1, 5));
    final b = ledger.swap(a, 6);
    expect((ledger.peakCount, ledger.peakBytes), (2, 11));
    ledger.release(b);
  });
}
