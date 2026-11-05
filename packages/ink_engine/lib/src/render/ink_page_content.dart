// lib/src/render/ink_page_content.dart — contract 7.2.15 (03-ink 4.8).
import 'dart:ui' show Size;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../background/background_spec.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_stroke.dart';

/// Immutable drawable snapshot of one page, built from CORE state (so every stroke carries
/// CORE's bounds).
@immutable
final class InkPageContent {
  InkPageContent._(this.page, this.strokes, this.revision);

  /// (v1.1) The ONLY constructor. Previews build a core.Page first, e.g.
  /// InkPageContent.fromCore(page: current.copyWith(size: s, background: b),
  ///     strokes: const [], revision: 0).
  ///
  /// Strokes with deletedAt != null are dropped; input already in core.Stroke.compareOrder
  /// is kept as is (checked in O(n)), otherwise sorted. Every stroke must belong to
  /// [page] (ArgumentError).
  factory InkPageContent.fromCore({
    required core.Page page,
    required List<core.Stroke> strokes,
    required int revision,
  }) {
    var active = <core.Stroke>[];
    var sorted = true;
    core.Stroke? previous;
    for (final s in strokes) {
      if (s.pageId != page.id) {
        throw ArgumentError.value(
          s.pageId,
          'strokes',
          'stroke ${s.id} belongs to another page than ${page.id}',
        );
      }
      if (s.deletedAt != null) continue;
      if (previous != null && core.Stroke.compareOrder(previous, s) > 0) {
        sorted = false;
      }
      active.add(s);
      previous = s;
    }
    if (!sorted) {
      active = List.of(active)..sort(core.Stroke.compareOrder);
    }
    return InkPageContent._(
      page,
      List.unmodifiable(active.map(InkStroke.of)),
      revision,
    );
  }

  final core.Page page;

  /// page.id
  String get pageId => page.id;

  /// page.size (pt)
  Size get pageSize => interop.sizeOf(page.size);

  /// InkBackgroundSpec.fromCore(page.background)
  InkBackgroundSpec get background => _background;
  late final InkBackgroundSpec _background = InkBackgroundSpec.fromCore(
    page.background,
  );

  /// bottom → top, unmodifiable
  final List<InkStroke> strokes;

  /// EDITOR passes core.PageContent.revision
  final int revision;

  late final Map<String, int> _index = {
    for (var i = 0; i < strokes.length; i++) strokes[i].id: i,
  };

  /// O(1)
  InkStroke? strokeById(String id) {
    final i = _index[id];
    return i == null ? null : strokes[i];
  }

  /// -1 if absent
  int zIndexOf(String id) => _index[id] ?? -1;

  /// Same page value, revision and the same stroke objects (identity, K-4).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InkPageContent ||
        other.revision != revision ||
        other.page != page ||
        other.strokes.length != strokes.length) {
      return false;
    }
    for (var i = 0; i < strokes.length; i++) {
      if (!identical(other.strokes[i].source, strokes[i].source)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(page, revision, strokes.length);

  @override
  String toString() =>
      'InkPageContent(${page.id}, ${strokes.length} strokes, revision $revision)';
}
