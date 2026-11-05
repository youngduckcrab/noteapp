/// The production start sequence (docs/plans/01-infra.md 4.5.9, contract
/// 7.3.3 order: core → pdf → featureWiring; M4 adds sync).
library;

import '../bootstrap/app_module.dart';
import 'core_module.dart';
import 'feature_wiring_module.dart';
import 'pdf_module.dart';

/// [CoreModule(), PdfModule(), FeatureWiringModule()] — ids unique.
List<AppModule> productionModules() => [
  CoreModule(),
  PdfModule(),
  FeatureWiringModule(),
];
