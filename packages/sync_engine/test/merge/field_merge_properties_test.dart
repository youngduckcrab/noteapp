import 'package:flutter_test/flutter_test.dart';

import '../shared/merge_properties_cases.dart';

void main() {
  // Seeds 1..20 × 100 pairs (6.3.2: 2,000 random pairs).
  group('FieldMerge properties', () {
    mergePropertiesCases(seeds: [for (var s = 1; s <= 20; s++) s]);
  });
}
