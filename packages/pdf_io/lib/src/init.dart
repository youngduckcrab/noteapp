// lib/src/init.dart — 06-pdf 4.1 (contract 7.2.19, 7.3.3 PdfModule row). One of the files
// allowed to import package:ink_engine (always `as ink`, 3).
//
// Foundation step B4 (T0, contract 7.6 B4): initializePdfIo does nothing; pdfIoOverrides()
// already returns its final two overrides. The PDF builder in the INK list was the paperOnly
// placeholder until PDF T9; it is now the renderer-backed builder, which reaches the render
// chain lazily (pdfBackgroundLayerBuilderProvider). Engine warm-up, the pdfrx configuration
// and the PDFium license registration come with PDF T17.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ink_engine/ink_engine.dart' as ink;

import 'config.dart';
import 'providers.dart';

/// Process-wide state behind initializePdfIo (internal, not exported).
abstract final class PdfIoRuntime {
  /// The config pdfIoConfigProvider falls back to. B4: initializePdfIo records nothing yet,
  /// so this is always the default config (T17 keeps the one given to initializePdfIo).
  static PdfIoConfig get config => const PdfIoConfig();
}

/// Idempotent and web-safe. Applies [config] (pdfrx wasm module URL), registers the PDFium
/// third-party notices with LicenseRegistry once (6.16), and when config.warmUpOnStart starts
/// engine initialization WITHOUT awaiting the wasm download (completes in < 10 ms).
/// Engine failures never throw here; they surface as PdfIoException(engineUnavailable) on
/// first PDF use. A second call with a different config is ignored (debug assert).
///
/// Contract 7.2.19: idempotent, < 10 ms. B4 (T0): does nothing.
Future<void> initializePdfIo({
  PdfIoConfig config = const PdfIoConfig(),
}) async {}

/// Overrides INFRA PdfModule adds to the root ProviderScope (contract 7.3.3). Always both:
///  - pdfIoConfigProvider.overrideWithValue(config ?? the config given to initializePdfIo)
///  - ink.pageBackgroundBuildersProvider.overrideWith((ref) =>
///      [ref.watch(pdfBackgroundLayerBuilderProvider), const ink.TemplateBackgroundLayerBuilder()])
/// The ONLY override of ink.pageBackgroundBuildersProvider in the app (contract 7.2.19).
/// When PdfModule failed to start, INFRA adds none of these (default = template builder only).
/// Reading ink.pageBackgroundBuildersProvider in a container that holds ONLY these overrides
/// never throws and builds nothing else (no engine, document pool, CORE gateway, renderer):
/// B4 (T0) uses PdfBackgroundLayerBuilder.paperOnly(); from T9 the builder reaches the
/// renderer lazily on its first build / renderStill (4.7, 4.12, PDF-2-2). The first PDF page
/// that is actually drawn needs core.noteStoreProvider (INFRA CoreModule starts first).
///
/// Contract 7.2.19: The ONLY override of ink.pageBackgroundBuildersProvider:
///   [pdfBackgroundLayerBuilder, const ink.TemplateBackgroundLayerBuilder()] (+ pdfIoConfigProvider).
List<Override> pdfIoOverrides({PdfIoConfig? config}) => [
  pdfIoConfigProvider.overrideWithValue(config ?? PdfIoRuntime.config),
  ink.pageBackgroundBuildersProvider.overrideWith(
    (ref) => <ink.PageBackgroundLayerBuilder>[
      ref.watch(pdfBackgroundLayerBuilderProvider),
      const ink.TemplateBackgroundLayerBuilder(),
    ],
  ),
];
