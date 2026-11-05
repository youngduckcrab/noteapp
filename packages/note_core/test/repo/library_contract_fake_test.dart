// CORE T8 — the shared LibraryRepository contract on createFakeNoteStore() (6.19).
import 'package:note_core/testing.dart';

import '../shared/library_contract.dart';

void main() =>
    defineLibraryContractTests((clock) => createFakeNoteStore(clock: clock));
