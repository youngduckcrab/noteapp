// CORE T19 — the backup document is generated and parsed in the browser (web compiler):
// the shared cases of 6.17 on the shared fake (same writer as the SQLite store). The
// SQLite store in the browser (WasmDatabase) joins with CORE T16.
@TestOn('browser')
library;

import 'package:test/test.dart';

import '../shared/backup_cases.dart';

void main() {
  defineBackupTests(open: openFakeBackupStore, seed: seedFakeBackupState);
}
