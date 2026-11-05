@TestOn('browser')
library;

// T13 / T13b / T21 (03-ink 9.1 '브라우저' row — 속지 벡터): the page-template
// vector rules (positions, widths, colors, the clip, music and planner) and
// the unclipped vectors the PDF export draws on the web also hold in Chrome
// (JS numbers).
import 'package:flutter_test/flutter_test.dart';

import '../unit/background/template_vectors_test.dart' as tv;
import '../unit/export/template_export_test.dart' as te;

void main() {
  group('template_vectors_test', tv.main);
  group('template_export_test', te.main);
}
