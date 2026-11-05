@TestOn('vm')
@Tags(['golden'])
library;

// T13 (03-ink 8, 6.16, 9.2): the four page templates (lined, grid, dotted,
// cornell) on white and black paper, drawn by TemplateBackgroundLayerBuilder
// at scale 0.475 (A4 → 282.76 × 399.90, captured 282 × 399 px so every
// pixel is paper — 9.2: ≤ 400 × 400, opaque) — 8 images.
// Update with: flutter test --update-goldens test/goldens/templates_golden_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/golden_frame.dart';

const _page = Size(595.2756, 841.8898);
const _viewScale = 0.475;

const _kinds = [
  core.PageTemplateKind.lined,
  core.PageTemplateKind.grid,
  core.PageTemplateKind.dotted,
  core.PageTemplateKind.cornell,
];

void main() {
  for (final kind in _kinds) {
    for (final (paperName, paper) in [
      ('white', core.PaperColors.white),
      ('black', core.PaperColors.black),
    ]) {
      final name = 'templates_${kind.name}_$paperName';
      testWidgets(name, (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(320, 440);
        addTearDown(tester.view.reset);
        final ctx = PageBackgroundContext(
          pageId: 'p1',
          pageSize: _page,
          background: InkBackgroundSpec.fromCore(
            core.TemplateBackground(
              template: core.PageTemplate.defaults(kind),
              paperColorArgb: paper,
            ),
          ),
          viewScale: _viewScale,
          ancestorScale: 1,
          devicePixelRatio: 1,
          isScaling: false,
        );
        await tester.pumpWidget(
          goldenFrame(
            _page * _viewScale,
            Builder(
              builder: (context) =>
                  const TemplateBackgroundLayerBuilder().build(context, ctx),
            ),
          ),
        );
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('images/$name.png'),
        );
      });
    }
  }
}
