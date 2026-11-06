// The recording contract (m5-7/02-core 6.6) on the real SQLite store (CORE T30) — the same
// body as test/repo/recording_contract_fake_test.dart.
@TestOn('vm')
library;

import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/recording_contract.dart';

void main() => defineRecordingContract(openTestNoteStore);
