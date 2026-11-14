// (v2.11, C211-01) The texture tiles' checksums (render/pens/texture/
// texture_tiles.dart): VM and Chrome must generate the same bytes (arithmetic
// only). byteChecksum (grain_checksum.dart) recorded on the VM.
const int recordedToothChecksum = 183416922;
const int recordedWashChecksum = 875238794;

/// Σ noise01(123456789, k) · (k mod 7 + 1) for k < 5000 and two single values
/// (texture_geometry.dart noise tables, strokeSalt), recorded on the VM.
const double recordedNoiseSum = 9996.016676074407;
const double recordedNoiseValue =
    0.42667950150867906; // noise01(1793750400, 17)
const int recordedStrokeSalt = 184353068; // strokeSalt(1793750400000)
