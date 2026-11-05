// lib/src/init.dart — 06-pdf 4.1 (contract 7.2.19, 7.3.3 PdfModule row). One of the files
// allowed to import package:ink_engine (always `as ink`, 3).
//
// Foundation step B4 (T0, contract 7.6 B4): initializePdfIo did nothing; pdfIoOverrides()
// already returned its final two overrides. The PDF builder in the INK list was the
// paperOnly placeholder until PDF T9; it is now the renderer-backed builder, which reaches
// the render chain lazily (pdfBackgroundLayerBuilderProvider). From PDF T17
// initializePdfIo keeps its config (pdfIoConfigProvider's default, the {max} of the error
// texts), applies it to pdfrx, registers the PDFium licenses once and starts the engine
// warm-up without awaiting it.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ink_engine/ink_engine.dart' as ink;

import 'config.dart';
import 'engine/pdf_engine.dart';
import 'engine/pdfrx_engine.dart';
import 'licenses.dart';
import 'providers.dart';

/// Process-wide state behind initializePdfIo (internal, not exported).
abstract final class PdfIoRuntime {
  static PdfIoConfig? _config;
  static bool _licensesRegistered = false;

  /// The config given to the first initializePdfIo; the default config before that.
  /// pdfIoConfigProvider falls back to it, PdfIoException.userMessage reads its limits.
  static PdfIoConfig get config => _config ?? const PdfIoConfig();

  /// Whether initializePdfIo has run.
  static bool get isInitialized => _config != null;

  /// The engine the warm-up initializes (tests only — default PdfrxEngine.shared()).
  @visibleForTesting
  static PdfEngine Function() warmUpEngine = PdfrxEngine.shared;

  /// Tests only: forget the config, the license registration and the warm-up engine.
  @visibleForTesting
  static void debugReset() {
    _config = null;
    _licensesRegistered = false;
    warmUpEngine = PdfrxEngine.shared;
  }
}

/// Idempotent and web-safe. Applies [config] (pdfrx wasm module URL), registers the PDFium
/// third-party notices with LicenseRegistry once (6.16), and when config.warmUpOnStart starts
/// engine initialization WITHOUT awaiting the wasm download (completes in < 10 ms).
/// Engine failures never throw here; they surface as PdfIoException(engineUnavailable) on
/// first PDF use. A second call with a different config is ignored (debug assert).
///
/// Contract 7.2.19: idempotent, < 10 ms.
///
/// T17: the first call keeps [config] (PdfIoRuntime.config), sets the pdfrx wasm module URL
/// (PdfrxEngine.configure — before any engine use), adds the PDFium license collector to
/// LicenseRegistry (licenses.dart — read only when the app lists its licenses) and, with
/// warmUpOnStart, calls ensureInitialized without awaiting it; a warm-up failure is left
/// for the first PDF use to show (engineUnavailable — the engine tries again then). A later
/// call returns at once; with a different config it asserts in debug builds.
Future<void> initializePdfIo({PdfIoConfig config = const PdfIoConfig()}) async {
  if (PdfIoRuntime._config case final first?) {
    assert(
      first == config,
      'initializePdfIo was called again with a different PdfIoConfig; the first one '
      'stays in effect.',
    );
    return;
  }
  PdfIoRuntime._config = config;
  PdfrxEngine.shared().configure(config);
  if (!PdfIoRuntime._licensesRegistered) {
    PdfIoRuntime._licensesRegistered = true;
    LicenseRegistry.addLicense(pdfiumLicenses);
  }
  if (config.warmUpOnStart) {
    final PdfEngine engine;
    try {
      engine = PdfIoRuntime.warmUpEngine();
    } on Object {
      return;
    }
    unawaited(
      Future.sync(engine.ensureInitialized).then<void>(
        (_) {},
        // Not reported: the same failure is shown on first use (engineUnavailable).
        onError: (Object _) {},
      ),
    );
  }
}

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
