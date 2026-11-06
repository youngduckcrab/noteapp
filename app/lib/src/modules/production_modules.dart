/// The production start sequence (docs/plans/01-infra.md 4.5.9; 2nd round
/// docs/plans/m5-7/01-infra.md 4.6.4, S2-1 — core → pdf → media →
/// recognition → featureWiring; M4 adds sync).
library;

import '../bootstrap/app_module.dart';
import '../features/app_features.dart';
import 'core_module.dart';
import 'feature_wiring_module.dart';
import 'media_module.dart';
import 'pdf_module.dart';
import 'recognition_module.dart';

/// The production start sequence. A module that is off at compile time is
/// not even constructed — dart2js drops what only it reaches (6.6:
/// FEATURE_MEDIA=false drops the recording path, not media_io's image import
/// used by FeatureWiringModule). Ids unique.
List<AppModule> productionModules() => [
  CoreModule(),
  PdfModule(),
  if (kFeatureMedia) MediaModule(),
  if (kFeatureRecognition) RecognitionModule(),
  FeatureWiringModule(),
];

/// Same list for tests with injected modules / features (V15): a module
/// whose feature is off in [features] is left out; a null argument is the
/// production module with default arguments.
List<AppModule> modulesFor({
  required AppFeatures features,
  CoreModule? core,
  PdfModule? pdf,
  MediaModule? media,
  RecognitionModule? recognition,
  FeatureWiringModule? wiring,
}) => [
  core ?? CoreModule(),
  pdf ?? PdfModule(),
  if (features.media) media ?? MediaModule(),
  if (features.recognition) recognition ?? RecognitionModule(),
  wiring ?? FeatureWiringModule(),
];
