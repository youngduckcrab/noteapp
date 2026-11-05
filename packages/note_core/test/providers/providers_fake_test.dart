// CORE providers on the fake store (8.1 T5, 6.16): the shared provider cases.
import 'package:note_core/testing.dart';

import '../shared/providers_contract.dart';

void main() {
  defineProviderContractTests(() async => createFakeNoteStore());
}
