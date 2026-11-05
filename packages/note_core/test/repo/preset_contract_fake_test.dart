// CORE T12 — the shared preset / settings rules on createFakeNoteStore() (6.19).
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../shared/preset_contract.dart';

void main() {
  group('presets', () {
    definePresetContractTests(createFakeNoteStore);
  });
  group('settings', () {
    defineSettingsContractTests(createFakeNoteStore);
  });
}
