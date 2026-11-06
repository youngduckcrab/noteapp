// lib/src/objects/object_factory.dart — m5-7/04-editor 5.1.1 'EDITOR 사용 규칙'
// (new objects: ids, page, createdAt, the page limit). (v2, E2-07a) the limit
// check first — paste needs it; (E2-09) the shape maker; the text box and
// image makers come with E2-10 and E2-12.
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
}
