// The search contract (m5-7/02-core 6.10.6, CP-14) on the real SQLite store — the same results,
// order and pagesTruncated as createFakeNoteStore (test/search/search_contract_fake_test.dart).
@TestOn('vm')
library;

import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/search_contract.dart';

void main() => defineSearchContract(openTestNoteStore);
