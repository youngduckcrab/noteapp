// lib/src/session/page_content.dart — contract 00-overview 7.2.8 / CORE 4.4.
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/page.dart';
import '../model/stroke.dart';

@immutable
final class PageContent {
  PageContent({
    required this.page,
    required List<Stroke> strokes,
    required this.revision,
  }) : strokes = List.unmodifiable(strokes);

  final Page page;

  /// Active strokes, ordered by Stroke.compareOrder, unmodifiable.
  final List<Stroke> strokes;

  /// Session-local counter, +1 per change of this page.
  final int revision;

  late final Map<ElementId, Stroke> _byId = {for (final s in strokes) s.id: s};

  /// O(1)
  Stroke? strokeById(ElementId id) => _byId[id];
  int get strokeCount => strokes.length;

  @override
  String toString() =>
      'PageContent(${page.id}, $strokeCount strokes, revision $revision)';
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
  // INK diffs by id + identity (K-4)
  final Set<ElementId> added, removed, updated;
  final bool pageChanged; // background/size changed

  @override
  String toString() =>
      'PageContentChange(${content.page.id}, ${origin.name}, +${added.length} '
      '-${removed.length} ~${updated.length}${pageChanged ? ', page' : ''})';
}
