@TestOn('browser')
library;

// T17 (03-ink 6.21, 9.1): the lasso rule tests — RDP, degeneracy, nonzero
// winding with the y-band index (= the plain winding on 10 000 random
// points), centerline coverage — also hold in Chrome (JS numbers).
import 'package:flutter_test/flutter_test.dart';

import '../unit/edit/lasso_test.dart' as lasso;

void main() {
  group('lasso_test', lasso.main);
}
