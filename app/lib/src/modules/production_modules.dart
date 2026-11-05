/// The production start sequence (docs/plans/01-infra.md 4.5.9, contract
/// 7.3.3 order: core → pdf → featureWiring; M4 adds sync).
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';

import '../bootstrap/app_module.dart';
import 'core_module.dart';
import 'pdf_module.dart';

/// [CoreModule(), PdfModule(), FeatureWiringModule()] — ids unique.
///
/// Until I10b brings FeatureWiringModule, the third module is the feature
/// packages' own override lists (the foundation step's wiring).
List<AppModule> productionModules() => [
  CoreModule(),
  PdfModule(),
  StaticOverridesModule(
    id: 'featureWiring',
    label: '화면 연결 중',
    overrides: [...featureEditorOverrides(), ...featureLibraryOverrides()],
  ),
];
