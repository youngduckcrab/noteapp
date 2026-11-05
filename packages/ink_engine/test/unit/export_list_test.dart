// The exported names of ink_engine's three entry points (03-ink 4.0 / 4.14, 8 T00):
// lib/ink_engine.dart and lib/dev_tools.dart export with `show` lists only, and those
// lists are exactly the names below; lib/testing.dart declares exactly the helpers of
// 4.14. Integration check R14 compares these names with the other packages (5.5).
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const Set<String> inkEngineNames = {
  // 4.0 show list
  'InkTuning',
  'InkLayer',
  'InkPoints',
  'InkStroke',
  'PenProfile', 'InkCap', 'InkRenderMethod',
  'StrokeStyleInk', 'InkStyleExtras', 'HighlighterStraightening',
  'InkSample', 'InkPointerKind',
  'InkSampleAdapter',
  'PressureMode', 'PressureModeNotifier',
  'PressureCapability', 'PressureSource', 'PressureCapabilityState',
  'PressureCapabilityStore', 'PressureCapabilityNotifier',
  'InkPredictor', 'NoopPredictor',
  'InkStrokeMeta',
  'InkVectorPath', 'InkPathVerb',
  'InkEdit', 'InkEditKind',
  'EraserSpec', 'EraserMode',
  'LassoOptions',
  'SelectionGeometry', 'SelectionHandle',
  'InkPageContent',
  'InkPageController', 'InkCoreServices', 'InkRenderLayer',
  'InkPageRenderStats',
  'InkGestureSession', 'StrokeSession', 'EraserSession', 'LassoSession',
  'LiveStrokeGeometry',
  'InkSelection',
  'InkPageView', 'InkPageGeometry',
  'InkRenderConfig',
  'InkCachePool', 'InkCacheStats',
  'PencilGrain',
  'InkPageThumbnail',
  'InkPageThumbnailRenderer',
  'PenPreviewPainter', 'PenPreviewShape',
  'InkBackgroundSpec', 'InkBackgroundKind',
  'PageBackgroundContext', 'PageBackgroundLayerBuilder',
  'PageBackgroundStillRenderer',
  'TemplateBackgroundLayerBuilder',
  'TemplateVectors', 'TemplateVectorItem', 'TemplateLine', 'TemplateDot',
  'InkVectorExport', 'InkPageVectors', 'InkHighlighterGroup',
  'InkHighlighterLine', 'InkFillShape', 'InkExportOptions', 'InkBlendMode',
  'InkClock',
  'InkDiagnostics', 'InkStatsSnapshot', 'LatencySummary',
  'inkRenderConfigProvider', 'inkClockProvider', 'pressureModeProvider',
  'pressureCapabilityProvider', 'inkCoreServicesProvider',
  'inkCachePoolProvider', 'inkDiagnosticsProvider', 'pencilGrainProvider',
  'pageBackgroundBuildersProvider', 'inkPageControllerProvider',
  'inkPageThumbnailRendererProvider',
};

const Set<String> devToolsNames = {'InkDevTools'};

const Set<String> testingNames = {
  'SyntheticInk',
  'FakeInkClock',
  'testInkCoreServices',
  'MemoryPressureStore',
  'SolidBackgroundBuilder',
  'createTestPageController',
};

/// Names removed from INK's public API by the contract (7.2.0, 7.2.15, 4.0).
const Set<String> removedNames = {
  'PenStyle',
  'InkTool',
  'InkToolX',
  'PressureCurve',
  'PaperColors',
  'PageTemplateKind',
  'PageTemplateSpec',
  'EraserFilter',
  'EraserFilterX',
  'kNominalQ',
  'kMaxWidthFactor',
  'InkAffine',
  'InkPointValue',
  'StrokeChange',
  'computeStrokeBounds',
  'InkThumbnailRenderer',
  'SequentialIds',
  'StrokeBuilder',
  'FinishedStroke',
  'buildStroke',
  'PressureDetector',
  'StrokeOutline',
  'OutlineGenerator',
  'OutlineOptions',
  'StrokeSpatialIndex',
  'InkHitTest',
  'PartialEraser',
  'LassoPolygon',
  'TemplateBackgroundPainter',
  'InkPointsBuilder',
};

String _read(String path) => File(path).readAsStringSync();

/// Every `export` directive of [source]: (uri, shown names or null without `show`).
List<(String, Set<String>?)> _exports(String source) {
  final out = <(String, Set<String>?)>[];
  final directive = RegExp(r'''^export\s+'([^']+)'([^;]*);''', multiLine: true);
  for (final m in directive.allMatches(source)) {
    final rest = m.group(2)!;
    final show = RegExp(r'\bshow\b([\s\S]*)').firstMatch(rest);
    out.add((
      m.group(1)!,
      show == null
          ? null
          : {
              for (final n in show.group(1)!.split(','))
                if (n.trim().isNotEmpty) n.trim(),
            },
    ));
  }
  return out;
}

Set<String> _shownNames(String path) {
  final names = <String>{};
  for (final (uri, shown) in _exports(_read(path))) {
    expect(shown, isNotNull, reason: '$path exports $uri without `show`');
    expect(
      uri,
      startsWith('src/'),
      reason: '$path re-exports another package ($uri)',
    );
    names.addAll(shown!);
  }
  return names;
}

/// Top-level declarations of a library file (classes, enums, extensions, typedefs,
/// functions and variables), found at column 0.
Set<String> _topLevelNames(String source) {
  final names = <String>{};
  final typeDecl = RegExp(
    r'^(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*'
    r'(?:class|enum|mixin|typedef|extension(?:\s+type)?)\s+(\w+)',
    multiLine: true,
  );
  for (final m in typeDecl.allMatches(source)) {
    names.add(m.group(1)!);
  }
  final function = RegExp(
    r'^[A-Za-z_][\w<>?, ]*\s+([a-z_]\w*)\(',
    multiLine: true,
  );
  for (final m in function.allMatches(source)) {
    names.add(m.group(1)!);
  }
  final variable = RegExp(
    r'^(?:final|const|var|late)\s+(?:[\w<>?, ]+\s+)?(\w+)\s*=',
    multiLine: true,
  );
  for (final m in variable.allMatches(source)) {
    names.add(m.group(1)!);
  }
  return names;
}

void main() {
  test('lib/ink_engine.dart show list = 03-ink 4.0', () {
    final names = _shownNames('lib/ink_engine.dart');
    expect(names, inkEngineNames);
    expect(names.intersection(removedNames), isEmpty);
  });

  test('lib/dev_tools.dart show list = 03-ink 4.14', () {
    expect(_shownNames('lib/dev_tools.dart'), devToolsNames);
  });

  test('lib/testing.dart top-level declarations = 03-ink 4.14', () {
    final source = _read('lib/testing.dart');
    expect(
      _exports(source),
      isEmpty,
      reason: 'testing.dart re-exports nothing',
    );
    expect(_topLevelNames(source), testingNames);
  });

  test('entry points do not overlap', () {
    expect(inkEngineNames.intersection(devToolsNames), isEmpty);
    expect(inkEngineNames.intersection(testingNames), isEmpty);
    expect(devToolsNames.intersection(testingNames), isEmpty);
  });
}
