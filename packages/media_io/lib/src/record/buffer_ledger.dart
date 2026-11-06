// lib/src/record/buffer_ledger.dart — m5-7/06-pdf 6.6.5 (M-4 '두 벌 넘게 들지 않음', C22-05).
// Internal.
//
// Counts the full-size recording buffers Dart holds on the stop and recovery paths: readAll,
// the unsaved join, the header patch (head + rest copied once, then the original dropped) and
// the bytes handed to AssetStore.put. A measuring hook only (integer additions — kept in release
// builds); tests read peakCount (≤ 2) and that everything is released at the end.
final class BufferLedger {
  int _nextId = 0;
  final Map<int, int> _held = {};
  int _bytes = 0;
  int _peakCount = 0, _peakBytes = 0;

  /// Buffers held now.
  int get count => _held.length;

  /// Their bytes.
  int get bytes => _bytes;

  /// Most buffers held at the same time since the start (or [resetPeaks]).
  int get peakCount => _peakCount;

  /// Most bytes held at the same time.
  int get peakBytes => _peakBytes;

  /// A new buffer of [length] bytes is held.
  BufferHold hold(int length) {
    final id = _nextId++;
    _held[id] = length;
    _bytes += length;
    _note();
    return BufferHold._(id, length);
  }

  /// A new buffer of [length] bytes replaces [old]: both are held for a moment (the copy), then
  /// [old] is let go ('잠깐 2 → 1').
  BufferHold swap(BufferHold old, int length) {
    final next = hold(length);
    release(old);
    return next;
  }

  /// [hold] is let go; releasing twice is a no-op.
  void release(BufferHold hold) {
    final length = _held.remove(hold._id);
    if (length != null) _bytes -= length;
  }

  /// Peaks start again from what is held now.
  void resetPeaks() {
    _peakCount = count;
    _peakBytes = _bytes;
  }

  void _note() {
    if (_held.length > _peakCount) _peakCount = _held.length;
    if (_bytes > _peakBytes) _peakBytes = _bytes;
  }
}

/// One held buffer (BufferLedger.hold / swap).
final class BufferHold {
  const BufferHold._(this._id, this.length);
  final int _id;
  final int length;
}
