/// PDF engine adapter (docs/plans/01-infra.md 4.5.9, contract 7.2.19 /
/// 7.3.3).
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pdf_io/pdf_io.dart';

import '../bootstrap/app_module.dart';

/// Initializes package:pdf_io. Non-critical: PDF failure must not block notes.
final class PdfModule extends AppModule {
  PdfModule({
    this._initialize = initializePdfIo,
    this._pdfOverrides = pdfIoOverrides,
  });

  static const String moduleId = 'pdf';

  final Future<void> Function() _initialize;
  final List<Override> Function() _pdfOverrides;

  @override
  String get id => moduleId;
  @override
  String get label => 'PDF 엔진 준비 중';
  @override
  bool get critical => false;
  @override
  Duration get startTimeout => const Duration(seconds: 10);

  /// await initialize() — returns in < 10 ms; the wasm warm-up is not
  /// awaited (계약 7.2.19).
  @override
  Future<void> start(AppModuleContext context) => _initialize();

  /// pdfOverrides(): the ONLY override of ink.pageBackgroundBuildersProvider
  /// (+ pdfIoConfigProvider). Not used when start failed → default builders
  /// (template only).
  @override
  List<Override> overrides() => _pdfOverrides();
}
