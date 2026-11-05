// Foundation step B8 start sequence (docs/plans/01-infra.md 8.1 B8-1):
// openNoteStore → root overrides → FoundationApp, or the notice when the
// store cannot be opened. The full bootstrap (modules, timeouts, startup
// error screen) is I5.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/app/foundation_app.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/foundation_bootstrap.dart';
import 'package:pdf_io/pdf_io.dart';

void _useIpadPortrait(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

void main() {
  testWidgets('an opened store is the root noteStoreProvider and the library '
      'shows', (tester) async {
    _useIpadPortrait(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final configs = <NoteStoreConfig>[];
    var pdfStarts = 0;

    final root = await buildFoundationRoot(
      open: (config) async {
        configs.add(config);
        return store;
      },
      initializePdf: () async {
        pdfStarts++;
      },
    );
    await tester.pumpWidget(root);
    await tester.pumpAndSettle();

    // INFRA-3-4: the temporary B8 entry point opens CORE's default config.
    expect(configs, [same(const NoteStoreConfig())]);
    expect(pdfStarts, 1);
    expect(find.byType(FoundationApp), findsOneWidget);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(FoundationStartupNotice), findsNothing);

    final container = _containerOf(tester);
    expect(container.read(noteStoreProvider), same(store));
    // pdfIoOverrides(): PDF placeholder builder + template builder.
    final builders = container.read(ink.pageBackgroundBuildersProvider);
    expect(builders, hasLength(2));
    expect(builders.first, isA<PdfBackgroundLayerBuilder>());
    expect(builders.last, isA<ink.TemplateBackgroundLayerBuilder>());
  });

  testWidgets('a failed PDF start leaves the PDF overrides out', (
    tester,
  ) async {
    _useIpadPortrait(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);

    final root = await buildFoundationRoot(
      open: (_) async => store,
      initializePdf: () async => throw StateError('pdf start failed'),
    );
    // Non-critical: reported, and the app still starts.
    expect(tester.takeException(), isA<StateError>());

    await tester.pumpWidget(root);
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    final builders = _containerOf(tester)
        .read(ink.pageBackgroundBuildersProvider);
    expect(builders, [isA<ink.TemplateBackgroundLayerBuilder>()]);
  });

  for (final (name, error) in <(String, Object)>[
    (
      'UnimplementedError (B2 openNoteStore)',
      UnimplementedError('openNoteStore arrives with CORE T6'),
    ),
    (
      'NoteStoreOpenException',
      const NoteStoreOpenException(
        NoteStoreOpenFailure.storageUnavailable,
        'no IndexedDB',
      ),
    ),
  ]) {
    testWidgets('a failed open ($name) is reported and shows only the notice', (
      tester,
    ) async {
      _useIpadPortrait(tester);
      var pdfStarts = 0;

      final root = await buildFoundationRoot(
        open: (_) => Future<NoteStore>.error(error),
        initializePdf: () async {
          pdfStarts++;
        },
      );
      expect(tester.takeException(), same(error));

      await tester.pumpWidget(root);
      await tester.pumpAndSettle();
      expect(find.byType(FoundationStartupNotice), findsOneWidget);
      expect(find.text(AppStrings.storeOpenFailed), findsOneWidget);
      expect(find.byType(FoundationApp), findsNothing);
      expect(find.byType(LibraryScreen), findsNothing);
      // Core failed first: PDF is not started.
      expect(pdfStarts, 0);
    });
  }

  test('foundationOverrides: core first, PDF only when started', () {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final withPdf = foundationOverrides(store, pdfStarted: true);
    final withoutPdf = foundationOverrides(store, pdfStarted: false);

    final featureCount =
        featureLibraryOverrides().length + featureEditorOverrides().length;
    expect(withoutPdf, hasLength(1 + featureCount));
    expect(withPdf, hasLength(1 + pdfIoOverrides().length + featureCount));

    // One container per list: Riverpod asserts on a provider overridden twice.
    for (final overrides in [withPdf, withoutPdf]) {
      final container = ProviderContainer.test(overrides: overrides);
      expect(container.read(noteStoreProvider), same(store));
    }
  });
}
