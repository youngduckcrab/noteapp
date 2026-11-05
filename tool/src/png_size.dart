/// Reads the width and height of a PNG file from its IHDR chunk
/// (`ws check` R13, docs/plans/01-infra.md 6.2).
library;

/// The 8-byte PNG signature.
const List<int> pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Returns the `(width, height)` of the PNG in [bytes], or `null` when the
/// bytes do not start with a PNG signature followed by an IHDR chunk.
({int width, int height})? pngSize(List<int> bytes) {
  // signature (8) + chunk length (4) + "IHDR" (4) + width (4) + height (4)
  if (bytes.length < 24) return null;
  for (var i = 0; i < pngSignature.length; i++) {
    if (bytes[i] != pngSignature[i]) return null;
  }
  const ihdr = [0x49, 0x48, 0x44, 0x52];
  for (var i = 0; i < 4; i++) {
    if (bytes[12 + i] != ihdr[i]) return null;
  }
  return (width: _uint32(bytes, 16), height: _uint32(bytes, 20));
}

int _uint32(List<int> bytes, int offset) =>
    ((bytes[offset] * 256 + bytes[offset + 1]) * 256 + bytes[offset + 2]) *
        256 +
    bytes[offset + 3];
