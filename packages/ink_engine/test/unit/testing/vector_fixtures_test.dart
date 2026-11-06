// T24 (m5-7/03-ink 8.1, 4.12): InkVectorFixtures — the eight factories take every
// public field of their value type; values rebuilt field by field from an
// exportPage result are == to it (the shape PDF uses before T42 is the real
// one); the defaults of 4.12.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

core.Stroke _stroke(String id, core.PenTool tool, int createdAt, double y) =>
    core.Stroke(
      id: id,
      pageId: 'p1',
      style: core.StrokeStyle.defaultsFor(tool),
      points: core.StrokePoints.fromInterleaved(
        Float32List.fromList([
          20, y, core.kNominalWidthQ, 0, 0, 0, //
          120, y + 10, core.kNominalWidthQ, 0, 0, 30,
          200, y, core.kNominalWidthQ, 0, 0, 60,
        ]),
      ),
      createdAt: createdAt,
    );

void main() {
  test('exportPage values rebuilt field by field are ==', () {
    final content = SyntheticInk.pageContent(
      strokes: [
        _stroke('h1', core.PenTool.highlighter, 1, 40),
        _stroke('b1', core.PenTool.ballpoint, 2, 80),
        _stroke('p1s', core.PenTool.pencil, 3, 120),
        _stroke('h2', core.PenTool.highlighter, 4, 160),
      ],
    );
    final real = InkVectorExport.exportPage(content);
    expect(real.inkShapes, hasLength(2));
    expect(real.highlighterGroups, isNotEmpty);
    expect(real.underlay, isEmpty);
    expect(real.annotations, isEmpty);
    expect(real.cover, isEmpty);
    expect(real.inkShapes.every((s) => s.objectId == null), isTrue);
    final rebuilt = InkVectorFixtures.pageVectors(
      highlighterGroups: [
        for (final g in real.highlighterGroups)
          InkVectorFixtures.highlighterGroup(
            colorArgb: g.colorArgb,
            opacity: g.opacity,
            blend: g.blend,
            lines: [
              for (final l in g.lines)
                InkVectorFixtures.highlighterLine(
                  strokeId: l.strokeId,
                  centerline: InkVectorPath(
                    Uint8List.fromList(l.centerline.verbs),
                    Float32List.fromList(l.centerline.coords),
                  ),
                  width: l.width,
                  cap: l.cap,
                ),
            ],
          ),
      ],
      inkShapes: [
        for (final s in real.inkShapes)
          InkVectorFixtures.fillShape(
            strokeId: s.strokeId,
            tool: s.tool,
            path: InkVectorPath(
              Uint8List.fromList(s.path.verbs),
              Float32List.fromList(s.path.coords),
            ),
            colorArgb: s.colorArgb,
            opacity: s.opacity,
            objectId: s.objectId,
          ),
      ],
      underlay: real.underlay,
      annotations: real.annotations,
      cover: real.cover,
      bounds: real.bounds,
    );
    expect(rebuilt, real);
    expect(rebuilt.hashCode, real.hashCode);
    // a changed field is a different value
    final changed = InkVectorFixtures.pageVectors(
      highlighterGroups: real.highlighterGroups,
      inkShapes: real.inkShapes.take(1).toList(),
      bounds: real.bounds,
    );
    expect(changed == real, isFalse);
  });

  test('every v2 value type and its defaults', () {
    final text = PageObjectFixtures.textBox(pageId: 'p1', id: 't1');
    final math = PageObjectFixtures.math(pageId: 'p1', id: 'm1');
    final path = InkVectorPath(
      Uint8List.fromList([0, 1, 1, 3]),
      Float32List.fromList([0, 0, 10, 0, 10, 10]),
    );
    final fill = InkVectorFixtures.fillShape(
      strokeId: 'sh1',
      tool: core.PenTool.ballpoint,
      path: path,
      colorArgb: 0xFF112233,
      objectId: 'sh1',
    );
    expect(fill.opacity, 1.0);
    expect(fill.objectId, 'sh1');
    final image = InkVectorFixtures.imageVector(
      assetId: 'a1',
      frame: const core.ElementFrame(core.PageRect(100, 100, 200, 150)),
      pixelWidth: 400,
      pixelHeight: 200,
    );
    expect(
      [image.assetId, image.pixelWidth, image.pixelHeight],
      ['a1', 400, 200],
    );
    final line = InkVectorFixtures.textLine(
      text: '안녕',
      x: 0,
      baselineY: 14,
      width: 30,
    );
    final textVector = InkVectorFixtures.textVector(
      object: text,
      lines: [line],
    );
    expect(textVector.frame, text.frame);
    expect(textVector.lines, [line]);
    expect(InkVectorFixtures.textVector(object: text).lines, isEmpty);
    final mathVector = InkVectorFixtures.mathVector(object: math);
    expect(mathVector.frame, math.frame);
    final List<InkAnnotationVector> annotations = [textVector, mathVector];
    final page = InkVectorFixtures.pageVectors(
      inkShapes: [fill],
      underlay: [image],
      annotations: annotations,
      cover: [fill],
    );
    // bounds left out → the union of the paths and frames
    expect(page.bounds, const Rect.fromLTRB(0, 0, 400, 650));
    expect(page.isEmpty, isFalse);
    expect(InkVectorFixtures.pageVectors().bounds, Rect.zero);
    expect(InkVectorFixtures.pageVectors().isEmpty, isTrue);
    // value equality
    expect(
      InkVectorFixtures.textLine(text: '안녕', x: 0, baselineY: 14, width: 30),
      line,
    );
    expect(InkVectorFixtures.mathVector(object: math), mathVector);
    expect(
      InkVectorFixtures.imageVector(
        assetId: 'a1',
        frame: const core.ElementFrame(core.PageRect(100, 100, 200, 150)),
        pixelWidth: 400,
        pixelHeight: 200,
      ),
      image,
    );
  });
}
