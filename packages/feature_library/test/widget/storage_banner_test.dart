// Storage warning banner (05-library 6.16.2, 8 L18; contract 7.2.12 /
// 7.4.5): CORE's storageWarningOf only. nativeFile → nothing; webInMemory →
// notDurable after the first pump without any write (persistenceStatusStream
// emits on listen), [닫기] hides it; three failed commits → writeFailing (no
// [닫기]) until CORE's retry (100 · 400 · 1600 ms, CORE 6.9) succeeds and the
// write Future completes. The texts are the LibraryStrings constants (L1
// strings_contract_test compares them with the contract's sentences).
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/ui/banners/storage_warning_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';

Finder bannerText(String text) => find.descendant(
  of: find.byType(StorageWarningBanner),
  matching: find.text(text),
);

Finder closeButton() => find.descendant(
  of: find.byType(StorageWarningBanner),
  matching: find.widgetWithText(TextButton, LibraryStrings.close),
);

void main() {
  testWidgets('nativeFile (the fake default): no banner', (tester) async {
    final backend = FakeLibraryBackend();
    addTearDown(backend.dispose);
    await LibraryTestHarness(backend).pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(StorageWarningBanner), findsOneWidget);
    expect(tester.getSize(find.byType(StorageWarningBanner)).height, 0);
    expect(bannerText(LibraryStrings.storageNotDurable), findsNothing);
    expect(bannerText(LibraryStrings.storageWriteFailing), findsNothing);
  });

  testWidgets('webInMemory: notDurable without a write; [닫기] hides it', (
    tester,
  ) async {
    final backend = FakeLibraryBackend(
      storageInfo: const StorageInfo(backend: StorageBackend.webInMemory),
    );
    addTearDown(backend.dispose);
    await LibraryTestHarness(backend).pump(tester);
    await tester.pump();
    expect(bannerText(LibraryStrings.storageNotDurable), findsOneWidget);
    expect(closeButton(), findsOneWidget);
    expect(
      tester.getSize(find.byType(StorageWarningBanner)).height,
      greaterThanOrEqualTo(48),
    );
    expect(backend.calls, isEmpty);

    await tester.tap(closeButton());
    await tester.pump();
    expect(bannerText(LibraryStrings.storageNotDurable), findsNothing);
    expect(tester.getSize(find.byType(StorageWarningBanner)).height, 0);
  });

  testWidgets('3 failed commits: writeFailing until the retry succeeds', (
    tester,
  ) async {
    final backend = FakeLibraryBackend();
    addTearDown(backend.dispose);
    await LibraryTestHarness(backend).pump(tester);
    await tester.pumpAndSettle();

    backend.faults!.failNextCommits(3);
    var written = false;
    final write = backend.store.library
        .createFolder(parentId: null, name: '실패 뒤 저장')
        .then((_) => written = true);
    await tester.pump(); // first attempt fails
    expect(bannerText(LibraryStrings.storageWriteFailing), findsNothing);
    await tester.pump(const Duration(milliseconds: 100)); // retry 1 fails
    await tester.pump(const Duration(milliseconds: 400)); // retry 2 fails
    expect(bannerText(LibraryStrings.storageWriteFailing), findsOneWidget);
    expect(closeButton(), findsNothing);
    expect(written, isFalse);

    await tester.pump(const Duration(milliseconds: 1600)); // retry 3 succeeds
    await tester.pump();
    expect(bannerText(LibraryStrings.storageWriteFailing), findsNothing);
    expect(written, isTrue);
    await write;
    await tester.pumpAndSettle();
  });

  testWidgets('a dismissed notDurable banner still shows writeFailing', (
    tester,
  ) async {
    final backend = FakeLibraryBackend(
      storageInfo: const StorageInfo(backend: StorageBackend.webInMemory),
    );
    addTearDown(backend.dispose);
    await LibraryTestHarness(backend).pump(tester);
    await tester.pump();
    await tester.tap(closeButton());
    await tester.pump();

    backend.faults!.failNextCommits(3);
    final write = backend.store.library.createFolder(
      parentId: null,
      name: '실패',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(bannerText(LibraryStrings.storageWriteFailing), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    // Back to notDurable, which stays dismissed for this screen.
    expect(bannerText(LibraryStrings.storageWriteFailing), findsNothing);
    expect(bannerText(LibraryStrings.storageNotDurable), findsNothing);
    await write;
    await tester.pumpAndSettle();
  });
}
