// Internal: EditCommand → AppliedEdit (CORE 6.5). Pure: validates and resolves against a
// read-only view of the session state and returns the deltas; it never mutates the state,
// so an invalid command changes nothing.
import 'package:collection/collection.dart';

import '../common/errors.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/sort_keys.dart';
import '../common/sort_planner.dart';
import '../model/page.dart';
import '../model/pen_style.dart';
import '../model/shape_geometry.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../sync/outbox_types.dart';
import 'applied_edit.dart';
import 'commands.dart';
import 'page_draft.dart';

/// Read-only view of the session state used by [CommandResolver].
abstract interface class ResolveState {
  NoteId get noteId;

  /// Active pages ordered by (sortKey, id).
  List<Page> get activePages;

  /// Active or deleted page known to the session.
  Page? knownPage(PageId id);

  /// Active strokes of a loaded page; null when the page is not loaded.
  Map<ElementId, Stroke>? activeStrokes(PageId pageId);

  /// (v2.0) Active page objects of a loaded page; null when the page is not loaded.
  Map<ElementId, PageObject>? activeObjects(PageId pageId);

  /// A (deleted) stroke id the session knows outside the loaded pages.
  bool isKnownStroke(ElementId id);

  /// (v2.0) A (deleted) page object id the session knows outside the loaded pages.
  bool isKnownObject(ElementId id);
}

/// (v2.0, m5-7/02-core 6.3) Field-version keys of a page object: its JSON keys minus the meta
/// keys (id, pageId, type, createdAt, updatedAt, version).
const Set<String> kObjectMetaKeys = {
  'id',
  'pageId',
  'type',
  'createdAt',
  'updatedAt',
  'version',
};

/// JSON keys whose values differ between [a] and [b], meta keys excluded (C-11 — only changed
/// keys get a new field version).
Set<String> changedObjectKeys(PageObject a, PageObject b) {
  final ja = a.toJson(), jb = b.toJson();
  const deep = DeepCollectionEquality();
  return {
    for (final k in {...ja.keys, ...jb.keys})
      if (!kObjectMetaKeys.contains(k) &&
          (ja.containsKey(k) != jb.containsKey(k) ||
              !deep.equals(ja[k], jb[k])))
        k,
  };
}

/// Result of [CommandResolver.resolve].
final class ResolvedEdit {
  ResolvedEdit(this.edit, this.changedFields);
  final AppliedEdit edit;

  /// JSON keys written per entity (6.5 '바뀐 필드'); {'*'} = all.
  final Map<EntityRef, Set<String>> changedFields;
}

int comparePages(Page a, Page b) =>
    compareSortKeyThenId(a.sortKey, a.id, b.sortKey, b.id);

final class CommandResolver {
  CommandResolver({required this.ids});
  final IdGenerator ids;

  /// Throws ArgumentError, PageNotOpenException, LastPageDeletionException. Pure: a throw
  /// (anywhere in a CompositeCommand) leaves the session as it was (6.4.1).
  ResolvedEdit resolve(
    EditCommand command,
    ResolveState state, {
    required EpochMillis now,
    required Hlc version,
  }) {
    final w = _Work(state, now, version, ids)..apply(command);
    return w.finish(command.label);
  }
}

/// (m5-7/02-core 6.2.3) The normalization of a LOCAL object write: styles by the 6.2.3 table,
/// frames (and an ellipse's frame) by ElementFrame.normalized(). UnknownObject as it is.
PageObject normalizedObject(PageObject o) => switch (o) {
  ShapeObject(:final geometry, :final style) => o.copyWith(
    geometry: geometry is EllipseGeometry
        ? EllipseGeometry(geometry.ellipseFrame.normalized())
        : geometry,
    style: style.normalized(),
  ),
  TextBoxObject(:final frame, :final style) => o.copyWith(
    frame: frame.normalized(),
    style: style.normalized(),
  ),
  ImageObject(:final frame) => o.copyWith(frame: frame.normalized()),
  MathObject(:final frame, :final style) => o.copyWith(
    frame: frame.normalized(),
    style: style.normalized(),
  ),
  UnknownObject() => o,
};

/// (m5-7/02-core 6.4.1) The local content limits of one object (ArgumentError).
void checkObjectLimits(PageObject o) {
  switch (o) {
    case TextBoxObject(:final text)
        when text.length > PageObjectLimits.maxTextLength:
      throw ArgumentError.value(
        text.length,
        'text.length',
        'object ${o.id}: at most ${PageObjectLimits.maxTextLength}',
      );
    case MathObject(:final latex)
        when latex.length > PageObjectLimits.maxLatexLength:
      throw ArgumentError.value(
        latex.length,
        'latex.length',
        'object ${o.id}: at most ${PageObjectLimits.maxLatexLength}',
      );
    case MathObject(:final ink)
        when ink.length > PageObjectLimits.maxMathInkStrokes:
      throw ArgumentError.value(
        ink.length,
        'ink.length',
        'object ${o.id}: at most ${PageObjectLimits.maxMathInkStrokes} strokes',
      );
    case MathObject(:final ink)
        when ink.fold<int>(0, (n, s) => n + s.points.length) >
            PageObjectLimits.maxMathInkPoints:
      throw ArgumentError.value(
        ink.fold<int>(0, (n, s) => n + s.points.length),
        'ink points',
        'object ${o.id}: at most ${PageObjectLimits.maxMathInkPoints} points',
      );
    case ShapeObject(geometry: PolylineGeometry(:final points))
        when points.length < 2 ||
            points.length > PageObjectLimits.maxPolylinePoints:
      throw ArgumentError.value(
        points.length,
        'points.length',
        'object ${o.id}: 2..${PageObjectLimits.maxPolylinePoints} points',
      );
    case ImageObject(:final pixelWidth, :final pixelHeight)
        when pixelWidth < 1 || pixelHeight < 1:
      throw ArgumentError.value(
        '${pixelWidth}x$pixelHeight',
        'pixelWidth / pixelHeight',
        'object ${o.id}: at least 1 × 1',
      );
    default:
      break;
  }
}

final class _Acc {
  _Acc(this.before, this.after, this.fields);
  final SyncEntity? before;
  SyncEntity after;
  final Set<String> fields;
}

final class _Work {
  _Work(this.state, this.now, this.v, this.ids);

  final ResolveState state;
  final EpochMillis now;
  final Hlc v;
  final IdGenerator ids;

  final Map<EntityRef, _Acc> _deltas = {};
  final Map<PageId, Page> _pages = {};

  /// Stroke overrides per page (null = no longer active).
  final Map<PageId, Map<ElementId, Stroke?>> _strokes = {};

  /// (v2.0) Page object overrides per page (null = no longer active).
  final Map<PageId, Map<ElementId, PageObject?>> _objects = {};

  /// Pages created by this edit: their stroke set starts empty.
  final Set<PageId> _newPages = {};
  final List<PageId> _insertedPages = [];
  final List<ElementId> _insertedElements = [];

  // ---- state view with overlay -------------------------------------------------

  Page? _page(PageId id) => _pages[id] ?? state.knownPage(id);

  List<Page> _activePages() {
    final map = {for (final p in state.activePages) p.id: p};
    for (final p in _pages.values) {
      if (p.isDeleted) {
        map.remove(p.id);
      } else {
        map[p.id] = p;
      }
    }
    return map.values.toList()..sort(comparePages);
  }

  Map<ElementId, Stroke> _base(PageId pageId) {
    if (_newPages.contains(pageId)) return const {};
    final base = state.activeStrokes(pageId);
    if (base == null) {
      throw PageNotOpenException('Page $pageId is not open in this session');
    }
    return base;
  }

  Stroke? _active(PageId pageId, ElementId id) {
    final o = _strokes[pageId];
    if (o != null && o.containsKey(id)) return o[id];
    return _base(pageId)[id];
  }

  Iterable<Stroke> _allActive(PageId pageId) sync* {
    final o = _strokes[pageId] ?? const <ElementId, Stroke?>{};
    for (final s in _base(pageId).values) {
      if (!o.containsKey(s.id)) yield s;
    }
    for (final s in o.values) {
      if (s != null) yield s;
    }
  }

  Map<ElementId, PageObject> _baseObjects(PageId pageId) {
    if (_newPages.contains(pageId)) return const {};
    final base = state.activeObjects(pageId);
    if (base == null) {
      throw PageNotOpenException('Page $pageId is not open in this session');
    }
    return base;
  }

  PageObject? _activeObject(PageId pageId, ElementId id) {
    final o = _objects[pageId];
    if (o != null && o.containsKey(id)) return o[id];
    return _baseObjects(pageId)[id];
  }

  Iterable<PageObject> _allActiveObjects(PageId pageId) sync* {
    final o = _objects[pageId] ?? const <ElementId, PageObject?>{};
    for (final x in _baseObjects(pageId).values) {
      if (!o.containsKey(x.id)) yield x;
    }
    for (final x in o.values) {
      if (x != null) yield x;
    }
  }

  /// Strokes and objects share ONE id space (6.4.1 — the 1st-round rule): the page, this edit,
  /// and the deleted ids the session knows.
  bool _strokeIdTaken(PageId pageId, ElementId id) {
    final o = _strokes[pageId];
    if (o != null && o.containsKey(id)) return true;
    if (_base(pageId).containsKey(id)) return true;
    if (_baseObjects(pageId).containsKey(id)) return true;
    for (final m in _strokes.values) {
      if (m.containsKey(id)) return true;
    }
    for (final m in _objects.values) {
      if (m.containsKey(id)) return true;
    }
    return state.isKnownStroke(id) || state.isKnownObject(id);
  }

  void _put(SyncEntity? before, SyncEntity after, Set<String> fields) {
    final ref = EntityRef(after.kind, after.id);
    final acc = _deltas[ref];
    if (acc == null) {
      _deltas[ref] = _Acc(before, after, {...fields});
    } else {
      acc.after = after;
      acc.fields.addAll(fields);
    }
    if (after is Page) {
      _pages[after.id] = after;
    } else if (after is Stroke) {
      (_strokes[after.pageId] ??= {})[after.id] = after.isDeleted
          ? null
          : after;
    } else if (after is PageObject) {
      (_objects[after.pageId] ??= {})[after.id] = after.isDeleted
          ? null
          : after;
    }
  }

  // ---- commands ---------------------------------------------------------------

  void apply(EditCommand c) {
    switch (c) {
      case AddStrokes(:final pageId, :final strokes):
        _base(pageId);
        _addStrokes(pageId, strokes);
      case RemoveStrokes(:final pageId, :final strokeIds):
        _base(pageId);
        _removeStrokes(pageId, strokeIds);
      case SplitStrokes(:final pageId, :final removedIds, :final added):
        _base(pageId);
        _removeStrokes(pageId, removedIds);
        _addStrokes(pageId, added);
      case TransformElements(
        :final pageId,
        :final elementIds,
        :final transform,
        :final scaleStrokeWidth,
      ):
        _base(pageId);
        _baseObjects(pageId);
        if (transform.isIdentity) return;
        for (final id in elementIds.toSet()) {
          final s = _active(pageId, id);
          if (s != null) {
            final t = s
                .transformed(transform, scaleWidth: scaleStrokeWidth)
                .copyWith(updatedAt: now, version: v);
            _put(s, t, {'points', if (t.style != s.style) 'style'});
            continue;
          }
          // (v2.0, m5-7/02-core 6.4.1) objects: THE transform rule (6.2.5), the same function
          // as every preview; UnknownObject cannot be transformed (skipped).
          final o = _activeObject(pageId, id);
          if (o == null || o is UnknownObject) continue;
          final t = o.transformed(transform, scaleWidth: scaleStrokeWidth);
          final keys = changedObjectKeys(o, t);
          if (keys.isEmpty) continue;
          _put(o, t.copyWithMeta(updatedAt: now, version: v), keys);
        }
      case RestyleStrokes(:final pageId, :final strokeIds, :final patch):
        _base(pageId);
        if (patch.isEmpty) return;
        for (final id in strokeIds.toSet()) {
          final s = _active(pageId, id);
          if (s == null) continue;
          final style = patch.applyTo(s.style);
          if (style == s.style) continue;
          _put(s, s.copyWith(style: style, updatedAt: now, version: v), {
            'style',
          });
        }
      case ClearPage(:final pageId, :final filter, :final includeObjects):
        _base(pageId);
        _baseObjects(pageId);
        // (v2.0) includeObjects: every PageObject, UnknownObject included (6.4.1).
        if (includeObjects) {
          _removeObjects(pageId, [
            for (final o in _allActiveObjects(pageId)) o.id,
          ]);
        }
        final ids = [
          for (final s in _allActive(pageId))
            if (switch (filter) {
              StrokeFilter.all => true,
              StrokeFilter.highlighterOnly =>
                s.style.tool == PenTool.highlighter,
              StrokeFilter.exceptHighlighter =>
                s.style.tool != PenTool.highlighter,
            })
              s.id,
        ];
        _removeStrokes(pageId, ids);
      case InsertPages(:final drafts, :final position):
        _insertPages(drafts, position);
      case DeletePages(:final pageIds):
        _deletePages(pageIds);
      case DuplicatePages(:final pageIds):
        _duplicatePages(pageIds);
      case MovePages(:final pageIds, :final position):
        _movePages(pageIds, position);
      case SetPageBackground(:final pageIds, :final background):
        for (final p in _targets(pageIds)) {
          if (p.background == background) continue;
          _put(
            p,
            p.copyWith(background: background, updatedAt: now, version: v),
            {'background'},
          );
        }
      case ResizePages(:final pageIds, :final size):
        final clamped = size.clamped();
        for (final p in _targets(pageIds)) {
          if (p.size == clamped) continue;
          _put(p, p.copyWith(size: clamped, updatedAt: now, version: v), {
            'size',
          });
        }
      case CompositeCommand(:final commands):
        commands.forEach(apply);
      case RemoveElements(:final pageId, :final elementIds):
        // (v2.0) strokes and objects; unknown / deleted / repeated ids ignored.
        _base(pageId);
        _baseObjects(pageId);
        _removeStrokes(pageId, elementIds);
        _removeObjects(pageId, elementIds);
      case AddObjects(:final pageId, :final objects):
        _base(pageId);
        _baseObjects(pageId);
        _addObjects(pageId, objects);
      case UpdateObjects(:final pageId, :final objects):
        _base(pageId);
        _baseObjects(pageId);
        _updateObjects(pageId, objects);
    }
  }

  // ---- (v2.0) page objects (m5-7/02-core 6.4.1) -----------------------------------------

  void _addObjects(PageId pageId, List<PageObject> objects) {
    final seen = <ElementId>{};
    for (final o in objects) {
      if (o.pageId != pageId) {
        throw ArgumentError(
          'Object ${o.id} belongs to page ${o.pageId}, not $pageId',
        );
      }
      if (o.version != null) {
        throw ArgumentError(
          'Object ${o.id} already has a version (must be null)',
        );
      }
      if (o.deletedAt != null) {
        throw ArgumentError('Object ${o.id} is deleted');
      }
      if (!isValidEntityId(o.id)) {
        throw ArgumentError.value(o.id, 'object.id', 'invalid entity id');
      }
      if (!seen.add(o.id) || _strokeIdTaken(pageId, o.id)) {
        throw ArgumentError.value(o.id, 'object.id', 'id already exists');
      }
      checkObjectLimits(o);
    }
    final count = _allActiveObjects(pageId).length + objects.length;
    if (count > PageObjectLimits.maxObjectsPerPage) {
      throw ArgumentError.value(
        count,
        'objects',
        'page $pageId: at most ${PageObjectLimits.maxObjectsPerPage} objects',
      );
    }
    for (final o in objects) {
      _put(null, normalizedObject(o).copyWithMeta(updatedAt: now, version: v), {
        kAllFields,
      });
      _insertedElements.add(o.id);
    }
  }

  void _updateObjects(PageId pageId, List<PageObject> objects) {
    final next = <(PageObject, PageObject)>[];
    final seen = <ElementId>{};
    for (final o in objects) {
      if (!seen.add(o.id)) {
        throw ArgumentError.value(o.id, 'object.id', 'listed twice');
      }
      final cur = _activeObject(pageId, o.id);
      if (cur == null) {
        throw ArgumentError.value(
          o.id,
          'object.id',
          'no active object on page $pageId',
        );
      }
      if (cur is UnknownObject || o is UnknownObject) {
        throw ArgumentError.value(
          o.id,
          'object',
          'an UnknownObject cannot be edited',
        );
      }
      if (cur.runtimeType != o.runtimeType || cur.type != o.type) {
        throw ArgumentError.value(o.id, 'object', 'the type cannot change');
      }
      if (o.pageId != cur.pageId || o.createdAt != cur.createdAt) {
        throw ArgumentError.value(
          o.id,
          'object',
          'pageId and createdAt cannot change (z-order is fixed)',
        );
      }
      if (o.deletedAt != null) {
        throw ArgumentError(
          'Object ${o.id} is deleted (remove it with RemoveElements)',
        );
      }
      checkObjectLimits(o);
      next.add((cur, normalizedObject(o)));
    }
    for (final (cur, o) in next) {
      final keys = changedObjectKeys(cur, o);
      if (keys.isEmpty) continue;
      _put(cur, o.copyWithMeta(updatedAt: now, version: v), keys);
    }
  }

  void _removeObjects(PageId pageId, List<ElementId> ids) {
    for (final id in ids.toSet()) {
      final o = _activeObject(pageId, id);
      if (o == null) continue; // unknown / already deleted ids are ignored
      _put(o, o.copyWithMeta(deletedAt: now, updatedAt: now, version: v), {
        'deletedAt',
      });
    }
  }

  void _addStrokes(PageId pageId, List<Stroke> strokes) {
    final seen = <ElementId>{};
    for (final s in strokes) {
      if (s.pageId != pageId) {
        throw ArgumentError(
          'Stroke ${s.id} belongs to page ${s.pageId}, not $pageId',
        );
      }
      if (s.version != null) {
        throw ArgumentError(
          'Stroke ${s.id} already has a version (must be null)',
        );
      }
      if (s.deletedAt != null) {
        throw ArgumentError('Stroke ${s.id} is deleted');
      }
      if (!isValidEntityId(s.id)) {
        throw ArgumentError.value(s.id, 'stroke.id', 'invalid entity id');
      }
      if (!seen.add(s.id) || _strokeIdTaken(pageId, s.id)) {
        throw ArgumentError.value(s.id, 'stroke.id', 'id already exists');
      }
    }
    for (final s in strokes) {
      final style = s.style.normalized();
      _put(null, s.copyWith(style: style, updatedAt: now, version: v), {
        kAllFields,
      });
      _insertedElements.add(s.id);
    }
  }

  void _removeStrokes(PageId pageId, List<ElementId> ids) {
    for (final id in ids.toSet()) {
      final s = _active(pageId, id);
      if (s == null) continue; // unknown / already deleted ids are ignored
      _put(s, s.copyWith(deletedAt: now, updatedAt: now, version: v), {
        'deletedAt',
      });
    }
  }

  List<Page> _targets(List<PageId> pageIds) {
    final ids = pageIds.toSet();
    return [
      for (final p in _activePages())
        if (ids.contains(p.id)) p,
    ];
  }

  int _anchorIndex(List<Page> order, PagePosition position) {
    int indexOf(PageId id) {
      final i = order.indexWhere((p) => p.id == id);
      if (i < 0) {
        throw ArgumentError.value(id, 'position', 'not an active page here');
      }
      return i;
    }

    return switch (position) {
      PageAtStart() => 0,
      PageAtEnd() => order.length,
      PageBefore(:final pageId) => indexOf(pageId),
      PageAfter(:final pageId) => indexOf(pageId) + 1,
    };
  }

  List<String> _placeKeys(List<Page> order, int index, int count) {
    final plan = planSortKeys(
      [for (final p in order) (key: p.sortKey, id: p.id)],
      index,
      count,
    );
    for (final e in plan.rekeyed.entries) {
      final p = _page(e.key)!;
      _put(p, p.copyWith(sortKey: e.value, updatedAt: now, version: v), {
        'sortKey',
      });
    }
    return plan.keys;
  }

  void _createPage(PageDraft draft, String sortKey) {
    final pageId = draft.id ?? ids.newId();
    if (!isValidEntityId(pageId)) {
      throw ArgumentError.value(pageId, 'draft.id', 'invalid entity id');
    }
    if (_page(pageId) != null) {
      throw ArgumentError.value(pageId, 'draft.id', 'page id already exists');
    }
    final page = Page(
      id: pageId,
      noteId: state.noteId,
      sortKey: sortKey,
      size: draft.size.clamped(),
      background: draft.background,
      createdAt: now,
      updatedAt: now,
      version: v,
    );
    // (v2.0) the draft's objects: limits before anything (6.4.1).
    if (draft.objects.length > PageObjectLimits.maxObjectsPerPage) {
      throw ArgumentError.value(
        draft.objects.length,
        'draft.objects',
        'at most ${PageObjectLimits.maxObjectsPerPage} objects per page',
      );
    }
    draft.objects.forEach(checkObjectLimits);
    _newPages.add(pageId);
    _put(null, page, {kAllFields});
    _insertedPages.add(pageId);
    for (final s in draft.strokes) {
      final copy = Stroke(
        id: ids.newId(),
        pageId: pageId,
        style: s.style.normalized(),
        points: s.points,
        recordingId: s.recordingId,
        recordingOffsetMs: s.recordingOffsetMs,
        createdAt: s.createdAt,
        updatedAt: now,
        version: v,
      );
      _put(null, copy, {kAllFields});
      _insertedElements.add(copy.id);
    }
    // (v2.0) objects: new ids, the original createdAt (z-order kept), normalized.
    for (final o in draft.objects) {
      final copy = normalizedObject(
        o.copyTo(id: ids.newId(), pageId: pageId, createdAt: o.createdAt),
      ).copyWithMeta(updatedAt: now, version: v);
      _put(null, copy, {kAllFields});
      _insertedElements.add(copy.id);
    }
  }

  void _insertPages(List<PageDraft> drafts, PagePosition position) {
    if (drafts.isEmpty) {
      throw ArgumentError('InsertPages needs at least one draft');
    }
    if (drafts.length > 2000) {
      throw ArgumentError.value(drafts.length, 'drafts', 'at most 2000 pages');
    }
    final order = _activePages();
    final keys = _placeKeys(
      order,
      _anchorIndex(order, position),
      drafts.length,
    );
    for (var i = 0; i < drafts.length; i++) {
      _createPage(drafts[i], keys[i]);
    }
  }

  void _deletePages(List<PageId> pageIds) {
    final targets = _targets(pageIds);
    if (targets.isEmpty) return;
    if (_activePages().length - targets.length < 1) {
      throw const LastPageDeletionException(
        'A note keeps at least one active page',
      );
    }
    for (final p in targets) {
      _put(p, p.copyWith(deletedAt: now, updatedAt: now, version: v), {
        'deletedAt',
      });
    }
  }

  void _duplicatePages(List<PageId> pageIds) {
    final sources = _targets(pageIds);
    for (final source in sources) {
      final strokes = _allActive(source.id).toList()..sort(Stroke.compareOrder);
      final objects = _allActiveObjects(source.id).toList()
        ..sort(Stroke.compareOrder);
      final order = _activePages();
      final index = order.indexWhere((p) => p.id == source.id) + 1;
      final key = _placeKeys(order, index, 1).single;
      _createPage(
        PageDraft(
          size: source.size,
          background: source.background,
          strokes: strokes,
          objects: objects,
        ),
        key,
      );
    }
  }

  void _movePages(List<PageId> pageIds, PagePosition position) {
    final moving = _targets(pageIds);
    if (moving.isEmpty) return;
    final movingIds = {for (final p in moving) p.id};
    final anchor = switch (position) {
      PageBefore(:final pageId) || PageAfter(:final pageId) => pageId,
      PageAtStart() || PageAtEnd() => null,
    };
    if (anchor != null && movingIds.contains(anchor)) {
      throw ArgumentError.value(anchor, 'position', 'anchor is being moved');
    }
    final rest = [
      for (final p in _activePages())
        if (!movingIds.contains(p.id)) p,
    ];
    final keys = _placeKeys(rest, _anchorIndex(rest, position), moving.length);
    for (var i = 0; i < moving.length; i++) {
      final p = _page(moving[i].id)!;
      if (p.sortKey == keys[i]) continue;
      _put(p, p.copyWith(sortKey: keys[i], updatedAt: now, version: v), {
        'sortKey',
      });
    }
  }

  ResolvedEdit finish(String label) {
    final deltas = <EntityDelta>[];
    final fields = <EntityRef, Set<String>>{};
    final affected = <PageId>{};
    for (final e in _deltas.entries) {
      final acc = e.value;
      // Created and deleted again inside one composite: nothing to write.
      if (acc.before == null && acc.after.isDeleted) continue;
      deltas.add(
        EntityDelta(
          kind: e.key.kind,
          id: e.key.id,
          before: acc.before,
          after: acc.after,
        ),
      );
      fields[e.key] = acc.fields.contains(kAllFields)
          ? {kAllFields}
          : acc.fields;
      final after = acc.after;
      if (after is PageElement) affected.add(after.pageId);
      if (after is Page) affected.add(after.id);
    }
    return ResolvedEdit(
      AppliedEdit(
        label: label,
        deltas: List.unmodifiable(deltas),
        version: v,
        affectedPageIds: Set.unmodifiable(affected),
        insertedPageIds: List.unmodifiable(
          _insertedPages.where(
            (id) => fields.containsKey(EntityRef(EntityKind.page, id)),
          ),
        ),
        insertedElementIds: List.unmodifiable([
          for (final id in _insertedElements)
            if (fields.containsKey(EntityRef(EntityKind.stroke, id)) ||
                fields.containsKey(EntityRef(EntityKind.pageObject, id)))
              id,
        ]),
      ),
      fields,
    );
  }
}
