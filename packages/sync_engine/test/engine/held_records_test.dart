// HeldRecords (07-sync 6.3.2, S2-6): the value of the sync.heldRecords keys. The bodies are
// shared with Chrome (test/web/pure_logic_browser_test.dart).
import 'package:flutter_test/flutter_test.dart';

import '../shared/held_records_cases.dart';

void main() {
  group('HeldRecords', heldRecordsCases);
}
