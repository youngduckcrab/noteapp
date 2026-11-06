// The object session contract (m5-7/02-core 6.5) on createFakeNoteStore(); the real store runs
// it from CORE T27 (page_objects in DB v2).
import 'package:note_core/testing.dart';

import '../shared/object_session_contract.dart';

void main() => defineObjectSessionContract(createFakeNoteStore);
