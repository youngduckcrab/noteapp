// lib/src/edit/page_draft.dart — contract 00-overview 7.2.7 / CORE 4.3.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/page_background.dart';
import '../model/page_size.dart';
import '../model/stroke.dart';
import '../session/page_content.dart';

sealed class PagePosition {
  const PagePosition();
}

final class PageAtStart extends PagePosition {
  const PageAtStart();
  @override
  bool operator ==(Object other) => other is PageAtStart;
  @override
  int get hashCode => 1;
}

final class PageAtEnd extends PagePosition {
  const PageAtEnd();
  @override
  bool operator ==(Object other) => other is PageAtEnd;
  @override
  int get hashCode => 2;
}

final class PageBefore extends PagePosition {
  const PageBefore(this.pageId);
  final PageId pageId;
  @override
  bool operator ==(Object other) =>
      other is PageBefore && other.pageId == pageId;
  @override
  int get hashCode => Object.hash('before', pageId);
}

final class PageAfter extends PagePosition {
  const PageAfter(this.pageId);
  final PageId pageId;
  @override
  bool operator ==(Object other) =>
      other is PageAfter && other.pageId == pageId;
  @override
  int get hashCode => Object.hash('after', pageId);
}

/// A page to be inserted. Stroke ids/pageIds are reassigned on insert;
/// stroke createdAt is preserved (keeps z-order of copies).
@immutable
final class PageDraft {
  const PageDraft({
    this.id,
    required this.size,
    required this.background,
    this.strokes = const [],
  });

  static const PageDraft blankA4 = PageDraft(
    size: PageSize.a4Portrait,
    background: BlankBackground(),
  );

  factory PageDraft.copyOf(PageContent content) => PageDraft(
    size: content.page.size,
    background: content.page.background,
    strokes: content.strokes,
  );

  final PageId? id; // null = generated
  final PageSize size;
  final PageBackground background;
  final List<Stroke> strokes;

  @override
  bool operator ==(Object other) =>
      other is PageDraft &&
      other.id == id &&
      other.size == size &&
      other.background == background &&
      const ListEquality<Stroke>().equals(other.strokes, strokes);

  @override
  int get hashCode => Object.hash(
    id,
    size,
    background,
    const ListEquality<Stroke>().hash(strokes),
  );
}
