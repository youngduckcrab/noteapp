@Tags(['integration'])
library;

// (v2.17-md, 08-markdown 15.4 '앱 끝까지(실제 CORE, VM)') The MD 문서 path of
// test/support/markdown_e2e_scenario.dart over the real CORE (in memory). Skipped by
// default (app/dart_test.yaml); run with `ws test --run-skipped -t integration`.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/modules/core_module.dart';

import '../fakes/fake_native_paths.dart';
import '../support/markdown_e2e_scenario.dart';

void main() {
  testWidgets('MD 문서 end to end over the real CORE (in memory)', (
    tester,
  ) async {
    await runMarkdownEndToEnd(
      tester,
      CoreModule(
        nativePaths: noNativePaths,
        configFor: (_) => const NoteStoreConfig(inMemory: true),
      ),
    );
  });
}
