// CORE T8 — the shared LibraryRepository contract on the SQLite store (openTestNoteStore).
@TestOn('vm')
library;

import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/library_contract.dart';

void main() => defineLibraryContractTests(
  (clock) => openTestNoteStore(clock: clock, seedDefaultPenPresets: false),
);
