// lib/src/compose/compose_backend.dart — 06-pdf 4.9, 6.11.4–6.11.7. The port only; the
// platform implementations are picked by compose_backend_factory.dart (6.15).
import 'dart:typed_data';

import '../export/compose_plan.dart';

abstract interface class PdfComposeJob {
  /// (2차, m5-7/06-pdf 4.1.4) A page may come as several parts, in one call or over several;
  /// the parts of the same outputIndex come in z order and each draws on top of what the page
  /// already has.
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
