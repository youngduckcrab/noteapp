// lib/src/compose/compose_backend.dart — 06-pdf 4.9, 6.11.4–6.11.7. The port only; the
// platform implementations are picked by compose_backend_factory.dart (6.15).
import 'dart:typed_data';

import '../export/compose_plan.dart';

abstract interface class PdfComposeJob {
  /// Pages must each be complete (a page's ops never span two calls).
  Future<void> addPages(List<PdfComposePageOps> pages);
  Future<Uint8List> finish();
  Future<void> abort(); // idempotent
}

abstract interface class PdfComposeBackend {
  bool get isSupported;

  /// Loads sources, imports pages (one import call per source), creates blank pages,
  /// orders them (6.11.4). Throws PdfIoException(exportFailed / engineUnavailable).
  Future<PdfComposeJob> begin(PdfComposePlan plan);
  Future<void> dispose();
}
