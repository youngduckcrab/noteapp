// test/shared/library_scenarios.dart — 05-library 5.7 / 8 L0, L21.
//
// Core scenarios run by widget/scenarios_on_fake_test.dart (the CORE fake,
// all of them) AND by integration/core_contract_test.dart (real CORE,
// needsFaults == false only — L21). A scenario only uses the harness, the
// backend's wrappers / seed helpers and the screen, so the same body gives the
// same result on both stores. Entries for the L21 list are added with the
// tasks that build the screens they need (L10 … L18).
import 'package:feature_library/feature_library.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/library_test_harness.dart';

typedef LibraryScenarioBody = Future<void> Function(
  WidgetTester tester,
  LibraryTestHarness h,
);

@immutable
final class LibraryScenario {
  const LibraryScenario(this.name, this.body, {this.needsFaults = false});

  final String name;
  final LibraryScenarioBody body;

  /// Uses h.backend.faults (CORE fake only). L21 runs only scenarios with
  /// needsFaults == false.
  final bool needsFaults;
}

/// Registered with testWidgets by widget/scenarios_on_fake_test.dart (all) and
/// by integration/core_contract_test.dart (needsFaults == false only).
final List<LibraryScenario> libraryScenarios = [
  LibraryScenario(
    'harness: a route change keeps the LibraryScreen State',
    _routeChangeKeepsState,
  ),
];

Future<void> _routeChangeKeepsState(
  WidgetTester tester,
  LibraryTestHarness h,
) async {
  final sample = await seedSampleLibrary(h.backend);
  await h.pump(tester);
  final state = tester.state(find.byType(LibraryScreen));
  expect(h.screen(tester).folderId, isNull);

  await h.goToFolder(tester, sample.math.id);
  expect(h.currentFolderId, sample.math.id);
  expect(h.screen(tester).folderId, sample.math.id);
  expect(tester.state(find.byType(LibraryScreen)), same(state));

  await h.goToFolder(tester, null);
  expect(h.screen(tester).folderId, isNull);
  expect(tester.state(find.byType(LibraryScreen)), same(state));
  // A route change made by the test is not a callback of the screen.
  expect(h.log.entries, isEmpty);
  expect(h.backend.calls, isEmpty);
}
