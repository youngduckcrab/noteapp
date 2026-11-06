// The handwriting contract (m5-7/02-core 6.9) on createFakeNoteStore(); the real store from
// CORE T32 (with the remote race case 3).
import 'package:note_core/testing.dart';

import '../shared/handwriting_contract.dart';

void main() => defineHandwritingContract(createFakeNoteStore);
