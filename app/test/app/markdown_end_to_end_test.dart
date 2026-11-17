// (v2.17-md, 08-markdown 15.4, MD-T11) The MD 문서 path end to end through the production
// app (modules, router, library, MD screen) over the fake CORE store: import → open →
// 보기 / 편집 → back → search → export → new → trash → restore
// (test/support/markdown_e2e_scenario.dart). The same path over the real CORE runs in
// the integration stage (test/integration/markdown_real_core_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/modules/core_module.dart';

import '../fakes/fake_native_paths.dart';
import '../support/markdown_e2e_scenario.dart';

void main() {
  testWidgets('MD 문서: import → view / edit → back → search → export → new → '
      'trash → restore (fake CORE)', (tester) async {
    await runMarkdownEndToEnd(
      tester,
      CoreModule(
        open: (_) async => createFakeNoteStore(),
        nativePaths: noNativePaths,
      ),
    );
  });
}
