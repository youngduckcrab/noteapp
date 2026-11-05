// The pencil grain checksum (T08, 03-ink 6.11, 9.1): VM and Chrome must
// generate the same bytes. Arithmetic only (no bit operations, every
// intermediate below 2^53).
import 'dart:typed_data';

/// Σ-style polynomial checksum of [bytes] modulo 1 000 000 007.
int byteChecksum(Uint8List bytes) {
  const m = 1000000007;
  var sum = 0;
  for (final b in bytes) {
    sum = (sum * 257 + b) % m;
  }
  return sum;
}

/// byteChecksum(PencilGrain.generatePixels()) recorded on the VM;
/// test/web/grain_checksum_test.dart expects the same value in Chrome.
const int recordedGrainChecksum = 120540651;
