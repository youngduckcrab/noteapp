/// PDF engine adapter (docs/plans/01-infra.md 4.5.9, contract 7.2.19 /
/// 7.3.3; 2nd round docs/plans/m5-7/01-infra.md 4.6.4 — the
/// pdf.searchIndexer idle task).
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pdf_io/pdf_io.dart';

import '../bootstrap/app_module.dart';
import '../bootstrap/idle_tasks.dart';
import 'idle_indexers.dart';
import 'pdf_share.dart';

/// Initializes package:pdf_io. Non-critical: PDF failure must not block notes.
final class PdfModule extends AppModule {
  PdfModule({
    this._initialize = initializePdfIo,
    this._pdfOverrides = pdfIoOverrides,
    this._indexer = readPdfSearchIndexer,
    this._share = platformPdfShare,
  });

  static const String moduleId = 'pdf';

  final Future<void> Function() _initialize;
  final List<Override> Function() _pdfOverrides;
  final IndexerHandleReader _indexer;
  final PdfShareFiles? _share;

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
  /// (+ pdfIoConfigProvider), then pdfShareFilesProvider = [share] (native:
  /// the system share sheet; web: null). Not used when start failed → INK's
  /// default builders ([image, template] — contract v2.2 7.3.3).
  @override
  List<Override> overrides() => [
    ..._pdfOverrides(),
    pdfShareFilesProvider.overrideWithValue(_share),
  ];

  /// [AppIdleTask(id: 'pdf.searchIndexer', priority:
  /// AppIdlePriority.searchIndex, run: (c) => runIndexerTask(c, indexer))]
  @override
  List<AppIdleTask> idleTasks() => [
    AppIdleTask(
      id: 'pdf.searchIndexer',
      priority: AppIdlePriority.searchIndex,
      run: (context) => runIndexerTask(context, _indexer),
    ),
  ];
}
