// PDF slots (05-library 4.3 / 6.8, 8 L18; contract 7.2.18): 새로 만들기 ›
// 'PDF 가져오기' (no slot → disabled '준비 중'; the folder of a folder
// section, else null; a returned id → onOpenNote only; null → nothing; an
// exception → reported + errorGeneric; one call at a time) and the note ⋯
// 'PDF로 내보내기' (no slot → hidden; [noteId]); both get the LibraryScreen
// State's context.
import 'dart:async';

import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';

/// Collects FlutterError reports during [body] (restored before returning).
Future<List<FlutterErrorDetails>> collectReports(
  Future<void> Function() body,
) async {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reports;
}

Finder menuItem(String label) => find.widgetWithText(MenuItemButton, label);

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<SampleLibrary> seed(WidgetTester tester) async =>
      (await tester.runAsync(() => seedSampleLibrary(backend)))!;

  Future<LibraryTestHarness> pumpAt(
    WidgetTester tester, {
    String? folderId,
    List<Override> overrides = const [],
  }) async {
    final h = LibraryTestHarness(backend, extraOverrides: overrides);
    await h.pump(tester, folderId: folderId);
    await tester.pumpAndSettle();
    return h;
  }

  BuildContext screenContext(WidgetTester tester) =>
      tester.state(find.byType(LibraryScreen)).context;

  Future<void> openNewMenu(WidgetTester tester) async {
    await tester.tap(find.text(LibraryStrings.newMenu));
    await tester.pumpAndSettle();
  }

  MenuItemButton importItem(WidgetTester tester) =>
      tester.widget<MenuItemButton>(
        find.ancestor(
          of: find.text(LibraryStrings.importPdf),
          matching: find.byType(MenuItemButton),
        ),
      );

  group('PDF 가져오기', () {
    testWidgets('no slot: disabled with 준비 중', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await openNewMenu(tester);
      expect(importItem(tester).onPressed, isNull);
      expect(find.text(LibraryStrings.comingSoon), findsOneWidget);
    });

    testWidgets('a folder section passes its folder; the id opens the note', (
      tester,
    ) async {
      final sample = await seed(tester);
      final calls = <(BuildContext, String?)>[];
      final h = await pumpAt(
        tester,
        folderId: sample.math.id,
        overrides: [
          libraryPdfImportActionProvider.overrideWithValue((
            context, {
            folderId,
          }) async {
            calls.add((context, folderId));
            return 'imported-note';
          }),
        ],
      );
      await openNewMenu(tester);
      expect(find.text(LibraryStrings.comingSoon), findsNothing);
      await tester.tap(menuItem(LibraryStrings.importPdf));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single.$2, sample.math.id);
      expect(calls.single.$1, same(screenContext(tester)));
      expect(h.log.entries, ['note:imported-note']);
      expect(backend.calls, isEmpty); // no markOpened
    });

    testWidgets('최근 (not a folder section) passes null', (tester) async {
      await seed(tester);
      final folders = <String?>['unset'];
      await pumpAt(
        tester,
        overrides: [
          libraryPdfImportActionProvider.overrideWithValue((
            context, {
            folderId,
          }) async {
            folders.add(folderId);
            return null;
          }),
        ],
      );
      await tester.tap(find.text(LibraryStrings.recent).first);
      await tester.pumpAndSettle();
      await openNewMenu(tester);
      await tester.tap(menuItem(LibraryStrings.importPdf));
      await tester.pumpAndSettle();
      expect(folders, ['unset', null]);
    });

    testWidgets('null (cancelled) does nothing', (tester) async {
      await seed(tester);
      final h = await pumpAt(
        tester,
        overrides: [
          libraryPdfImportActionProvider.overrideWithValue(
            (context, {folderId}) async => null,
          ),
        ],
      );
      await openNewMenu(tester);
      await tester.tap(menuItem(LibraryStrings.importPdf));
      await tester.pumpAndSettle();
      expect(h.log.entries, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an exception: reported once, errorGeneric snack bar', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(
        tester,
        overrides: [
          libraryPdfImportActionProvider.overrideWithValue(
            (context, {folderId}) async => throw StateError('pdf failed'),
          ),
        ],
      );
      final reports = await collectReports(() async {
        await openNewMenu(tester);
        await tester.tap(menuItem(LibraryStrings.importPdf));
        await tester.pumpAndSettle();
      });
      expect(reports, hasLength(1));
      expect(reports.single.library, 'feature_library');
      expect(find.text(LibraryStrings.errorGeneric), findsOneWidget);
      expect(h.log.entries, isEmpty);
    });

    testWidgets('disabled while an import runs; one call', (tester) async {
      await seed(tester);
      final pending = Completer<String?>();
      var count = 0;
      final h = await pumpAt(
        tester,
        overrides: [
          libraryPdfImportActionProvider.overrideWithValue((
            context, {
            folderId,
          }) {
            count++;
            return pending.future;
          }),
        ],
      );
      await openNewMenu(tester);
      await tester.tap(menuItem(LibraryStrings.importPdf));
      await tester.pumpAndSettle();
      await openNewMenu(tester);
      expect(importItem(tester).onPressed, isNull);
      await tester.tap(menuItem(LibraryStrings.importPdf));
      await tester.pumpAndSettle();
      expect(count, 1);
      await tester.tapAt(Offset.zero); // close the menu
      await tester.pumpAndSettle();

      pending.complete('n1');
      await tester.pumpAndSettle();
      expect(h.log.entries, ['note:n1']);
      await openNewMenu(tester);
      expect(importItem(tester).onPressed, isNotNull);
    });
  });

  group('PDF로 내보내기 (⋯)', () {
    testWidgets('no slot: not in the note menu', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await tester.tap(find.byTooltip(LibraryStrings.itemMenu('일기')));
      await tester.pumpAndSettle();
      expect(menuItem(LibraryStrings.rename), findsOneWidget);
      expect(menuItem(LibraryStrings.exportPdfOne), findsNothing);
    });

    testWidgets("[noteId] with the screen's context; not for folders", (
      tester,
    ) async {
      final sample = await seed(tester);
      final calls = <(BuildContext, List<String>)>[];
      await pumpAt(
        tester,
        overrides: [
          libraryPdfExportActionProvider.overrideWithValue((
            context,
            noteIds,
          ) async {
            calls.add((context, noteIds));
          }),
        ],
      );
      await tester.tap(find.byTooltip(LibraryStrings.itemMenu('수학')));
      await tester.pumpAndSettle();
      expect(menuItem(LibraryStrings.exportPdfOne), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(LibraryStrings.itemMenu('일기')));
      await tester.pumpAndSettle();
      await tester.tap(menuItem(LibraryStrings.exportPdfOne));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single.$2, [sample.homeNotes[3].id]);
      expect(calls.single.$1, same(screenContext(tester)));
      expect(backend.calls, isEmpty);
    });
  });

  test('featureLibraryOverrides() is empty', () {
    expect(featureLibraryOverrides(), isEmpty);
  });
}
