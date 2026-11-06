// Compose encoder v2 (m5-7/06-pdf 4.1.4, 6.2.6; 8.2 T21): image / text ops (placement, argument
// counts), byteLength, parts cut before the 8 MiB limit, a 16 MiB RGBA image alone in its part,
// a font only on the first part that uses it, empty paths skipped, the backends' ops checks
// (an image after an open path → ArgumentError) and RecordingComposeBackend v2. The 1차 cases
// stay in unit/compose_encoder_test. The cases live in support/compose_v2_cases.dart (the
// browser twin is web/pure_logic_browser_test).
import '../support/compose_v2_cases.dart';

void main() => encoderV2Cases();
