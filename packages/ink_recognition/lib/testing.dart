/// Test helpers of ink_recognition (contract m5-7/00-overview 7.6 '기반 단계
/// 시험 도우미', m5-7/05-library 4.3): fake engines, fixed-seed synthetic
/// handwriting and synthetic shape paths. Web safe; no flutter_test import.
/// Import from `test/` only (contract 7.1 rule 2).
library;

export 'src/testing/fake_recognizers.dart'
    show FakeHandwritingRecognizer, FakeMathRecognizer;
export 'src/testing/synthetic_handwriting.dart' show SyntheticHandwriting;
export 'src/testing/synthetic_shapes.dart' show SyntheticShapes;
