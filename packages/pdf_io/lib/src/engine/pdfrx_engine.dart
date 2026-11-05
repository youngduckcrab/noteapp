// lib/src/engine/pdfrx_engine.dart — 06-pdf 4.3. The only pdf_io file (with init.dart and
// compose/compose_backend_native.dart) that imports package:pdfrx, always `as rx` (3).
//
// Foundation step B4 (T0): the singleton only (configure() is a no-op). pdfrx is not
// imported yet; configuration, initialization, open, render and text come with PDF T3.
import 'dart:typed_data';

import '../config.dart';
import 'page_info.dart';
import 'pdf_engine.dart';

/// Production engine over pdfrx 2.11.0. Process-wide singleton (init is global in pdfrx).
final class PdfrxEngine implements PdfEngine {
  factory PdfrxEngine.shared() => _shared;

  PdfrxEngine._();

  static final PdfrxEngine _shared = PdfrxEngine._();

  /// Applies config before the first ensureInitialized(); later calls are ignored.
  void configure(PdfIoConfig config) {
    // B4 (T0): there is no engine to configure yet (pdfrx comes with PDF T3).
  }

  @override
  bool get isInitialized => false;

  @override
  Future<void> ensureInitialized() =>
      throw UnimplementedError('PdfrxEngine.ensureInitialized (PDF T3)');

  @override
  Future<PdfEngineDocument> open(
    Uint8List bytes, {
    required String sourceName,
    String fileName = '',
    PdfPasswordCallback? onPassword,
    int maxPasswordAttempts = 5,
    bool transferOwnership = false,
  }) => throw UnimplementedError('PdfrxEngine.open (PDF T3)');
}
