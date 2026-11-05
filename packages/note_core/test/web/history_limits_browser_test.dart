@TestOn('browser')
library;

import 'package:test/test.dart';

import '../shared/history_limits_cases.dart';

void main() => defineHistoryLimitsTests(web: true);
