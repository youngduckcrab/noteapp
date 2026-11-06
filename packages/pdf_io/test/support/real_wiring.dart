// The PDF provider graph wired as the app wires it (contract 7.3.3) — taken out of the 1차
// integration/real_wiring_test.dart (m5-7/06-pdf 8.2 T29, PDF-M14) so the 2nd-round V11 tests
// (integration/export_objects_v11_test.dart VM, web/export_objects_v11_browser_test.dart Chrome)
// and V10's PDF part (integration/search_indexer_core_test.dart) use the SAME wiring:
//   CoreModule           core.noteStoreProvider → the store the test opened (real CORE:
//                        note_core/testing_vm.dart openTestNoteStore on the VM,
//                        note_core/testing_web.dart openWebTestNoteStore in Chrome),
//   PdfModule            pdfIoOverrides() (real PDFium through pdfrx, the platform compose
//                        backend — native FFI / web Worker — and InkEngineVectorizer),
//   FeatureWiringModule  core.pageThumbnailRendererProvider → ink.inkPageThumbnailRendererProvider.
// Nothing PDF-side is overridden. Web-safe (no dart:io): the caller opens the store and starts
// PDFium (VM: support/pdfium_env.dart initPdfiumForTests; web: PdfrxEngine.configure with the
// files of tool/prepare_web_test.dart).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';

/// The app's root overrides for these providers (contract 7.3.3), in module order, over
/// [store]. [config] defaults to no warm-up (tests start PDFium themselves).
final class RealWiring {
  RealWiring(
    this.store, {
    PdfIoConfig config = const PdfIoConfig(warmUpOnStart: false),
  }) : container = ProviderContainer(
         overrides: [
           // CoreModule
           core.noteStoreProvider.overrideWithValue(store),
           // PdfModule
           ...pdfIoOverrides(config: config),
           // FeatureWiringModule
           core.pageThumbnailRendererProvider.overrideWith(
             (ref) => ref.watch(ink.inkPageThumbnailRendererProvider),
           ),
         ],
       );

  final core.NoteStore store;
  final ProviderContainer container;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  /// PdfImportService.open → commit → dispose, as the import sheet does.
  Future<PdfImportResult> import(
    Uint8List bytes,
    PdfImportTarget target, {
    PdfPageRange range = const PdfPageRange.all(),
    String fileName = 'lecture.pdf',
  }) async {
    final session = await read(pdfImportServiceProvider)
        .open(PickedPdfFile.fromBytes(fileName, bytes));
    try {
      return await session.commit(target, range: range);
    } finally {
      await session.dispose();
    }
  }

  /// Every hit of the 1차 PdfTextService.searchNote for [query] (the stream ends done).
  Future<List<PdfSearchHit>> search(core.NoteId noteId, String query) async {
    final events = await read(pdfTextServiceProvider)
        .searchNote(noteId, query)
        .toList();
    expect(events.last.isDone, isTrue, reason: 'search for $query');
    return [for (final e in events) ...e.newHits];
  }

  /// Disposes the container (closes the pool's documents and the compose backend) and then
  /// the store.
  Future<void> close() async {
    container.dispose();
    await store.close();
  }
}
