@TestOn('browser')
library;

// T16 (03-ink 6.20 성질 ④, 9.1): the partial-eraser property test, cut down
// to 50 cases, in Chrome (JS numbers) — properties ①–⑤ hold and the result
// checksum equals the VM one.
import 'package:flutter_test/flutter_test.dart';

import '../support/partial_eraser_properties.dart';

void main() {
  test('6.20 properties ①–⑤ over 50 random cases; checksum = VM', () {
    expect(checkPartialEraserProperties(50), partialEraserChecksum50);
  });
}
