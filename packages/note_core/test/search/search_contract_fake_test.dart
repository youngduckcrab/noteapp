// The search contract (m5-7/02-core 6.10.6, CP-14) on createFakeNoteStore(); the real store
// and Chrome from CORE T33b.
import 'package:note_core/testing.dart';

import '../shared/search_contract.dart';

void main() => defineSearchContract(createFakeNoteStore);
