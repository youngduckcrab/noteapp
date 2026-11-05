// E-13: storage warning banner and storage error snack bar (04-editor
// 6.17.3, EDITOR-S2, contract 7.2.12 v1.1 / 7.4.5 v1.1).
import 'package:feature_editor/src/ui/banners/storage_warning_banner.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const List<Offset> _points = [
  Offset(100, 150),
  Offset(140, 170),
  Offset(190, 185),
];

void main() {
  testWidgets('the default fake store (nativeFile) shows no banner', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.pump();
    expect(find.byKey(StorageWarningBanner.bannerKey), findsNothing);
    expect(find.text(EditorStrings.storageNotDurable), findsNothing);
    expect(find.text(EditorStrings.storageWriteFailing), findsNothing);
  });

  testWidgets('webInMemory → the notDurable banner one pump after opening', (
    tester,
  ) async {
    final store = createFakeNoteStore(
      storageInfo: const core.StorageInfo(
        backend: core.StorageBackend.webInMemory,
      ),
    );
    addTearDown(store.close);
    await pumpEditor(tester, store: store, settle: false);
    await tester.pump();
    expect(find.text(EditorStrings.storageNotDurable), findsOneWidget);
    expect(find.byKey(StorageWarningBanner.bannerKey), findsOneWidget);
  });

  testWidgets('three failed commits in a row → the writeFailing banner, '
      'gone after the retry succeeds', (tester) async {
    final faults = FakeNoteStoreFaults();
    final store = createFakeNoteStore(faults: faults);
    final h = await pumpEditor(tester, store: store);
    faults.failNextCommits(3);
    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    // Retries after 100 ms and 400 ms fail too (fake WriteQueue schedule).
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text(EditorStrings.storageWriteFailing), findsNothing);
    await tester.pump(const Duration(milliseconds: 450));
    expect(store.persistenceStatus.consecutiveFailures, 3);
    expect(find.text(EditorStrings.storageWriteFailing), findsOneWidget);
    expect(find.text(EditorStrings.storageErrorSnack), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(store.persistenceStatus.consecutiveFailures, 0);
    expect(find.text(EditorStrings.storageWriteFailing), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await store.close();
  });

  testWidgets('one failed commit → a snack bar only', (tester) async {
    final faults = FakeNoteStoreFaults();
    final store = createFakeNoteStore(faults: faults);
    final h = await pumpEditor(tester, store: store);
    faults.failNextCommits(1);
    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    await tester.pump();
    await tester.pump();
    expect(find.text(EditorStrings.storageErrorSnack), findsOneWidget);
    expect(find.byKey(StorageWarningBanner.bannerKey), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(store.persistenceStatus.consecutiveFailures, 0);
    expect(find.byKey(StorageWarningBanner.bannerKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await store.close();
  });
}
