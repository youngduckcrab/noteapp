// Pure logic of media_io that must give the same results under dart2js as on the VM (m5-7/06-pdf
// 9.1; contract 7.4 — web-safe numbers: no 64-bit reads, arithmetic instead of bit operations).
// (T32a) The WebM timeline and header patch hand samples and the MP4 length cases — the same
// assertions as unit/webm_timeline_test and unit/mp4_duration_test.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/mp4_duration_cases.dart';
import '../support/webm_timeline_cases.dart';

void main() {
  group('webm timeline', webmTimelineCases);
  group('mp4 duration', mp4DurationCases);
}
