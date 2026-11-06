// lib/src/objects/object_factory.dart — m5-7/04-editor 5.1.1 'EDITOR 사용 규칙'
// (new objects: ids, page, createdAt, the page limit). (v2, E2-07a) the limit
// check first — paste needs it; (E2-09) the shape maker; (E2-10) the text
// box maker of a dragged box; (E2-12) the image maker.
import 'dart:ui' show Rect;

import 'package:note_core/note_core.dart' as core;

abstract final class ObjectFactory {
  /// (5.1.1) Whether adding [adding] objects to [content] would go over
  /// PageObjectLimits.maxObjectsPerPage — then no command is sent and the
  /// user is told (6.21: EditorStrings.objectLimitReached).
  static bool exceedsLimit(core.PageContent content, int adding) =>
      adding > 0 &&
      content.objectCount + adding > core.PageObjectLimits.maxObjectsPerPage;

  /// (E2-09, 5.1.1) A new shape on [pageId]: a new id ([newId] —
  /// core.idGeneratorProvider), [createdAt] (clock now), version null, the
  /// style normalized.
  static core.ShapeObject shape({
    required String pageId,
    required core.ShapeKind kind,
    required core.ShapeGeometry geometry,
    required core.ShapeStyle style,
    required String Function() newId,
    required core.EpochMillis createdAt,
  }) => core.ShapeObject(
    id: newId(),
    pageId: pageId,
    shapeKind: kind,
    geometry: geometry,
    style: style.normalized(),
    createdAt: createdAt,
  );

  /// (E2-10, 6.11.1) A new, empty text box over [rectPt] (page pt — the
  /// dragged outline: width at least 40, height one line; the session
  /// measures it): a new id, [createdAt], the style normalized. Not stored
  /// until its edit session ends with text (6.11.5).
  static core.TextBoxObject textBox({
    required String pageId,
    required Rect rectPt,
    required core.TextBoxStyle style,
    required String Function() newId,
    required core.EpochMillis createdAt,
  }) => core.TextBoxObject(
    id: newId(),
    pageId: pageId,
    frame: core.ElementFrame(
      core.PageRect.fromLTWH(
        rectPt.left,
        rectPt.top,
        rectPt.width,
        rectPt.height,
      ),
    ),
    text: '',
    style: style.normalized(),
    createdAt: createdAt,
  );

  /// (E2-12, 6.12.2 step 4) A new image over [rectPt] (page pt —
  /// ObjectPlacement.forImage, rotation 0) showing [imported]'s asset: a new
  /// id, [createdAt], the pixel size of the stored bytes.
  static core.ImageObject image({
    required String pageId,
    required Rect rectPt,
    required core.ImportedImage imported,
    required String Function() newId,
    required core.EpochMillis createdAt,
  }) => core.ImageObject(
    id: newId(),
    pageId: pageId,
    frame: core.ElementFrame(
      core.PageRect.fromLTWH(
        rectPt.left,
        rectPt.top,
        rectPt.width,
        rectPt.height,
      ),
    ),
    assetId: imported.asset.id,
    pixelWidth: imported.pixelWidth,
    pixelHeight: imported.pixelHeight,
    createdAt: createdAt,
  );
}
