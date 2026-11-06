@TestOn('browser')
library;

// PDF T28 (m5-7/06-pdf 6.4.5, C2-27): PdfTextNormalizer == CORE SearchText under dart2js — the
// same cases as unit/normalizer_equivalence_test (U+0130, final sigma and \s differ between
// platforms when left to toLowerCase / RegExp).
import 'package:flutter_test/flutter_test.dart';

import '../support/normalizer_equivalence_cases.dart';

void main() {
  defineNormalizerEquivalenceCases();
}
