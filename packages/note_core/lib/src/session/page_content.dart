// lib/src/session/page_content.dart — contract 00-overview 7.2.8 / CORE 4.4. (v2.0) objects —
// 2nd-round contract 7.2.3 / 02-core 4.4.
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/page.dart';
import '../model/stroke.dart';

@immutable
final class PageContent {
  PageContent({
    required this.page,
    required List<Stroke> strokes,
    List<PageObject> objects = const [],
    required this.revision,
  }) : strokes = List.unmodifiable(strokes),
       objects = List.unmodifiable(objects);

  final Page page;

  /// Active strokes, ordered by Stroke.compareOrder, unmodifiable.
  final List<Stroke> strokes;

  /// (v2.0, 2nd-round contract 7.2.3) active only, Stroke.compareOrder; unmodifiable.
  final List<PageObject> objects;

  /// Session-local counter, +1 per change of this page.
  final int revision;

  late final Map<ElementId, Stroke> _byId = {for (final s in strokes) s.id: s};
  late final Map<ElementId, PageObject> _objectsById = {
    for (final o in objects) o.id: o,
  };

  /// O(1)
  Stroke? strokeById(ElementId id) => _byId[id];
  int get strokeCount => strokes.length;

  /// (v2.0) O(1)
  PageObject? objectById(ElementId id) => _objectsById[id];

  /// (v2.0) stroke or object
  PageElement? elementById(ElementId id) => _byId[id] ?? _objectsById[id];

  /// (v2.0)
  int get objectCount => objects.length;

  @override
  String toString() =>
      'PageContent(${page.id}, $strokeCount strokes, $objectCount objects, '
      'revision $revision)';
}

enum ChangeOrigin { load, local, undo, redo, remote }

@immutable
final class PageContentChange {
  const PageContentChange({
    required this.content,
    required this.origin,
    this.added = const {},
    this.removed = const {},
    this.updated = const {},
    this.pageChanged = false,
  });

  final PageContent content;
  final ChangeOrigin origin;
  // INK diffs by id + identity (K-4). (v2.0) element ids — strokes AND objects (2nd-round
  // contract 7.2.3, C2-10); consumers ignore ids they do not know.
  final Set<ElementId> added, removed, updated;
  final bool pageChanged; // background/size changed

  @override
  String toString() =>
      'PageContentChange(${content.page.id}, ${origin.name}, +${added.length} '
      '-${removed.length} ~${updated.length}${pageChanged ? ', page' : ''})';
}
