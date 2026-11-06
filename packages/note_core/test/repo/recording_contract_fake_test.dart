// The recording contract (m5-7/02-core 6.6) on createFakeNoteStore(); the real store from
// CORE T30.
import 'package:note_core/testing.dart';

import '../shared/recording_contract.dart';

void main() => defineRecordingContract(createFakeNoteStore);
