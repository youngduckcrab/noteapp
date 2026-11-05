import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart';
import 'package:pdf_io/pdf_io.dart';

import '../app/foundation_app.dart';
import '../routing/app_routes.dart';

/// Opens the note store (CORE openNoteStore shape, contract 7.2.12).
typedef FoundationStoreOpener = Future<NoteStore> Function(
  NoteStoreConfig config,
);

/// Starts PDF (pdf_io initializePdfIo shape, contract 7.2.19).
typedef FoundationPdfInitializer = Future<void> Function();

/// Temporary start sequence of foundation step B8 (docs/plans/01-infra.md
/// 8.1 B8-1). Returns the root widget for runApp:
///
/// 1. core: `open(const NoteStoreConfig())`. On ANY failure — including the
///    B2 UnimplementedError — the error is reported and only
///    [FoundationStartupNotice] is shown.
/// 2. pdf (non-critical): `initializePdf()`; on failure the PDF overrides are
///    left out (contract 7.3.3: default = template backgrounds only).
/// 3. ProviderScope with [foundationOverrides] → [FoundationApp].
///
/// INFRA-3-4: `const NoteStoreConfig()` uses CORE's relative static file
/// paths. That is fine here because B1/B8 CI does not deploy; I5 replaces this
/// with runNoteApp + CoreModule's defaultNoteStoreConfig (absolute URLs
/// against document.baseURI, contract 7.2.12 / 7.4.3), timeouts and the
/// startup error screen.
Future<Widget> buildFoundationRoot({
  FoundationStoreOpener open = openNoteStore,
  FoundationPdfInitializer initializePdf = initializePdfIo,
  String initialLocation = AppRoutes.library,
}) async {
  final NoteStore store;
  try {
    store = await open(const NoteStoreConfig());
  } on Object catch (error, stack) {
    _report(error, stack, 'while opening the note store');
    return const FoundationStartupNotice();
  }

  var pdfStarted = false;
  try {
    await initializePdf();
    pdfStarted = true;
  } on Object catch (error, stack) {
    _report(error, stack, 'while starting pdf_io (non-critical)');
  }

  return ProviderScope(
    overrides: foundationOverrides(store, pdfStarted: pdfStarted),
    child: FoundationApp(initialLocation: initialLocation),
  );
}

/// The root overrides of the foundation step, in module order core → pdf →
/// feature wiring (contract 7.3.3). Only the rows the placeholder screens
/// need: CORE's noteStoreProvider, PDF's pdfIoOverrides() (the only override
/// of ink.pageBackgroundBuildersProvider, contract 7.2.19) when PDF started,
/// and the feature packages' own override lists. The other
/// FeatureWiringModule rows (thumbnail renderer, PDF actions, editor
/// extensions, dev overlay) come with I10b.
List<Override> foundationOverrides(
  NoteStore store, {
  required bool pdfStarted,
}) => <Override>[
  noteStoreProvider.overrideWithValue(store),
  if (pdfStarted) ...pdfIoOverrides(),
  ...featureLibraryOverrides(),
  ...featureEditorOverrides(),
];

void _report(Object error, StackTrace stack, String context) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'noteapp',
      context: ErrorDescription(context),
    ),
  );
}
