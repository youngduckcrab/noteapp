// Object commands (m5-7/02-core 6.4.1 table): validation before any change, deltas and changed
// fields, strokes + objects in one transform step, ClearPage.includeObjects, RemoveElements with
// repeated ids, draft / duplicate copies keeping createdAt, a failing composite changes nothing,
// the 2,000 per page limit, undo / redo. Resolver level (changed fields) and session level on the
// fake store (memory state). Web-safe.
import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/edit/command_resolver.dart';
import 'package:note_core/src/sync/outbox_types.dart' as outbox;
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

const _now = 5000;
const _v = Hlc(5000, 0, '0000000000000001');
const _pageId = 'p1';

final class _State implements ResolveState {
  _State(this.strokes, this.objects, {this.knownObjects = const {}});
  final Map<ElementId, Stroke> strokes;
  final Map<ElementId, PageObject> objects;
  final Set<ElementId> knownObjects;
  final Page page = const Page(
    id: _pageId,
    noteId: 'n1',
    sortKey: 'a0',
    size: PageSize.a4Portrait,
    background: BlankBackground(),
    createdAt: 0,
    updatedAt: 0,
    version: Hlc(1, 0, '0000000000000001'),
  );

  @override
  NoteId get noteId => 'n1';
  @override
  List<Page> get activePages => [page];
  @override
  Page? knownPage(PageId id) => id == _pageId ? page : null;
  @override
  Map<ElementId, Stroke>? activeStrokes(PageId pageId) =>
      pageId == _pageId ? strokes : null;
  @override
  Map<ElementId, PageObject>? activeObjects(PageId pageId) =>
      pageId == _pageId ? objects : null;
  @override
  bool isKnownStroke(ElementId id) => false;
  @override
  bool isKnownObject(ElementId id) => knownObjects.contains(id);
}

ShapeObject _shape(String id, {int createdAt = 10, PageId pageId = _pageId}) =>
    ShapeObject(
      id: id,
      pageId: pageId,
      shapeKind: ShapeKind.rectangle,
      geometry: ShapeGeometry.rectangle(const PageRect(0, 0, 100, 50)),
      style: const ShapeStyle(strokeColorArgb: 0xFF000000),
      createdAt: createdAt,
    );

TextBoxObject _text(String id, {String text = '안녕', int createdAt = 11}) =>
    TextBoxObject(
      id: id,
      pageId: _pageId,
      frame: const ElementFrame(PageRect(0, 100, 200, 140)),
      text: text,
      style: const TextBoxStyle(),
      createdAt: createdAt,
    );

/// [o] as the session would hold it after an add (version set).
T _stored<T extends PageObject>(T o) =>
    o.copyWithMeta(updatedAt: 1, version: const Hlc(1, 0, '0000000000000001'))
        as T;

void main() {
  final resolver = CommandResolver(ids: SequentialIdGenerator(prefix: 'new'));
  late Stroke stroke;
  setUp(() {
    stroke = StrokeFixtures.synthetic(
      pageId: _pageId,
      ids: SequentialIdGenerator(prefix: 's'),
    ).copyWith(version: _v);
  });

  ResolvedEdit resolve(EditCommand c, _State state) =>
      resolver.resolve(c, state, now: _now, version: _v);

  Set<String> fieldsOf(ResolvedEdit r, String id) =>
      r.changedFields[outbox.EntityRef(EntityKind.pageObject, id)]!;

  group('AddObjects', () {
    test('validation: ArgumentError for each rule', () {
      final state = _State({stroke.id: stroke}, {'o1': _stored(_shape('o1'))});
      final bad = <String, PageObject>{
        'page': _shape('a1', pageId: 'p2'),
        'version': _shape('a2').copyWithMeta(version: _v),
        'deleted': _shape('a3').copyWithMeta(deletedAt: 1),
        'id': _shape('bad id!'),
        'id = stroke': _shape(stroke.id),
        'id = object': _shape('o1'),
        'text': _text('a4', text: 'x' * (PageObjectLimits.maxTextLength + 1)),
        'latex': MathObject(
          id: 'a5',
          pageId: _pageId,
          frame: const ElementFrame(PageRect(0, 0, 1, 1)),
          latex: 'x' * (PageObjectLimits.maxLatexLength + 1),
          style: const MathStyle(),
          createdAt: 1,
        ),
        'one point': _shape('a6').copyWith(
          geometry: const PolylineGeometry([PagePoint(0, 0)], closed: false),
        ),
        '65 points': _shape('a7').copyWith(
          geometry: PolylineGeometry([
            for (var i = 0; i <= PageObjectLimits.maxPolylinePoints; i++)
              PagePoint(i.toDouble(), 0),
          ], closed: false),
        ),
        'image 0 px': ImageObject(
          id: 'a8',
          pageId: _pageId,
          frame: const ElementFrame(PageRect(0, 0, 1, 1)),
          assetId: 'a' * 64,
          pixelWidth: 0,
          pixelHeight: 10,
          createdAt: 1,
        ),
      };
      for (final MapEntry(key: name, value: o) in bad.entries) {
        expect(
          () => resolve(AddObjects(pageId: _pageId, objects: [o]), state),
          throwsArgumentError,
          reason: name,
        );
      }
      expect(
        () => resolve(
          AddObjects(pageId: _pageId, objects: [_shape('d'), _shape('d')]),
          state,
        ),
        throwsArgumentError,
        reason: 'repeated in the command',
      );
      expect(
        () => resolve(
          AddObjects(pageId: _pageId, objects: [_shape('k')]),
          _State({}, {}, knownObjects: {'k'}),
        ),
        throwsArgumentError,
        reason: 'a deleted object id the session knows',
      );
      expect(
        () => resolve(AddObjects(pageId: 'p9', objects: [_shape('x')]), state),
        throwsA(isA<PageNotOpenException>()),
      );
    });

    test('at most 2,000 active objects per page after the command', () {
      final base = {
        for (var i = 0; i < PageObjectLimits.maxObjectsPerPage - 1; i++)
          'b$i': _stored(_shape('b$i')),
      };
      final state = _State({}, base);
      expect(
        resolve(
          AddObjects(pageId: _pageId, objects: [_shape('ok')]),
          state,
        ).edit.deltas,
        hasLength(1),
      );
      expect(
        () => resolve(
          AddObjects(pageId: _pageId, objects: [_shape('x1'), _shape('x2')]),
          state,
        ),
        throwsArgumentError,
      );
    });

    test('normalized, stamped, {*}, inserted ids; UnknownObject accepted', () {
      final raw = ShapeObject(
        id: 'n1',
        pageId: _pageId,
        shapeKind: ShapeKind.ellipse,
        geometry: ShapeGeometry.ellipse(
          const PageRect(0, 0, 10, 10),
          rotation: 3 * math.pi,
        ),
        style: const ShapeStyle(strokeColorArgb: 0x00112233, strokeWidth: 99),
        createdAt: 7,
      );
      final unknown = UnknownObject({
        'id': 'u1',
        'pageId': _pageId,
        'type': 'sticker',
        'createdAt': 8,
        'updatedAt': 8,
      });
      final r = resolve(
        AddObjects(pageId: _pageId, objects: [raw, unknown]),
        _State({}, {}),
      );
      final added = r.edit.deltas.first.after! as ShapeObject;
      expect(added.style.strokeColorArgb, 0xFF112233);
      expect(added.style.strokeWidth, 30);
      expect(added.frame.rotation, closeTo(math.pi, 1e-12));
      expect(added.updatedAt, _now);
      expect(added.version, _v);
      expect(added.createdAt, 7);
      expect(r.edit.deltas.first.before, isNull);
      expect(fieldsOf(r, 'n1'), {kAllFields});
      expect(r.edit.insertedElementIds, ['n1', 'u1']);
      expect(r.edit.affectedPageIds, {_pageId});
      final u = r.edit.deltas.last.after! as UnknownObject;
      expect(u.rawJson['type'], 'sticker');
      expect(u.version, _v);
    });
  });

  group('UpdateObjects', () {
    final text = _stored(_text('t1'));
    final shape = _stored(_shape('s1'));
    final unknown = _stored(
      UnknownObject({
        'id': 'u1',
        'pageId': _pageId,
        'type': 'sticker',
        'createdAt': 8,
        'updatedAt': 8,
      }),
    );
    _State state() => _State({}, {'t1': text, 's1': shape, 'u1': unknown});

    test('validation: ArgumentError before any change', () {
      final bad = <String, List<PageObject>>{
        'missing': [_text('zz')],
        'type': [
          ShapeObject(
            id: 't1',
            pageId: _pageId,
            shapeKind: ShapeKind.line,
            geometry: ShapeGeometry.line(
              const PagePoint(0, 0),
              const PagePoint(1, 1),
            ),
            style: const ShapeStyle(strokeColorArgb: 1),
            createdAt: 11,
          ),
        ],
        'unknown stored': [unknown],
        'unknown given': [
          UnknownObject({
            'id': 's1',
            'pageId': _pageId,
            'type': 'shape',
            'createdAt': 10,
            'updatedAt': 10,
          }),
        ],
        'createdAt': [_text('t1', createdAt: 99)],
        'deleted': [text.copyWithMeta(deletedAt: 1)],
        'limit': [text.copyWith(text: 'x' * 10001)],
        'listed twice': [text.copyWith(text: 'a'), text.copyWith(text: 'b')],
        'one bad of two': [text.copyWith(text: 'fine'), _text('zz')],
      };
      for (final MapEntry(key: name, value: objects) in bad.entries) {
        expect(
          () => resolve(
            UpdateObjects(pageId: _pageId, objects: objects),
            state(),
          ),
          throwsArgumentError,
          reason: name,
        );
      }
    });

    test('only changed JSON keys; no delta when nothing changed', () {
      final r = resolve(
        UpdateObjects(
          pageId: _pageId,
          objects: [text.copyWith(text: '바뀜')],
        ),
        state(),
      );
      expect(fieldsOf(r, 't1'), {'text'});
      final after = r.edit.deltas.single.after! as TextBoxObject;
      expect(after.text, '바뀜');
      expect(after.updatedAt, _now);
      expect(after.version, _v);
      expect(r.edit.deltas.single.before, text);

      final styled = resolve(
        UpdateObjects(
          pageId: _pageId,
          objects: [
            text.copyWith(
              style: const TextBoxStyle(bold: true),
              frame: const ElementFrame(PageRect(0, 100, 300, 140)),
            ),
          ],
        ),
        state(),
      );
      expect(fieldsOf(styled, 't1'), {'style', 'frame'});

      final same = resolve(
        UpdateObjects(pageId: _pageId, objects: [text, shape]),
        state(),
      );
      expect(same.edit.isEmpty, isTrue);
      // Normalization first: an alpha-less color equal after normalization is no change.
      final alpha = resolve(
        UpdateObjects(
          pageId: _pageId,
          objects: [
            shape.copyWith(
              style: const ShapeStyle(strokeColorArgb: 0x00000000),
            ),
          ],
        ),
        state(),
      );
      expect(alpha.edit.isEmpty, isTrue);
    });
  });

  group('RemoveElements, ClearPage(includeObjects:)', () {
    test('strokes and objects; repeated / unknown / deleted ids ignored', () {
      final o = _stored(_shape('o1'));
      final r = resolve(
        RemoveElements(
          pageId: _pageId,
          elementIds: [stroke.id, 'o1', 'o1', 'nope', stroke.id],
        ),
        _State({stroke.id: stroke}, {'o1': o}),
      );
      expect(r.edit.deltas, hasLength(2));
      expect(fieldsOf(r, 'o1'), {'deletedAt'});
      final removed = r.edit.deltas
          .firstWhere((d) => d.kind == EntityKind.pageObject)
          .after!;
      expect(removed.isDeleted, isTrue);
      expect(removed.version, _v);
    });

    test('includeObjects removes every object (UnknownObject too)', () {
      final objects = {
        'o1': _stored(_shape('o1')),
        'u1': _stored(
          UnknownObject({
            'id': 'u1',
            'pageId': _pageId,
            'type': 'x',
            'createdAt': 1,
            'updatedAt': 1,
          }),
        ),
      };
      final all = resolve(
        const ClearPage(pageId: _pageId, includeObjects: true),
        _State({stroke.id: stroke}, objects),
      );
      expect(all.edit.deltas, hasLength(3));
      final strokesOnly = resolve(
        const ClearPage(pageId: _pageId),
        _State({stroke.id: stroke}, objects),
      );
      expect(strokesOnly.edit.deltas.single.kind, EntityKind.stroke);
      final highlighter = resolve(
        const ClearPage(
          pageId: _pageId,
          filter: StrokeFilter.highlighterOnly,
          includeObjects: true,
        ),
        _State({stroke.id: stroke}, objects),
      );
      expect(highlighter.edit.deltas.map((d) => d.kind).toSet(), {
        EntityKind.pageObject,
      });
    });
  });

  group('TransformElements', () {
    test('strokes and objects in one edit; the single transform rule', () {
      final text = _stored(_text('t1'));
      final shape = _stored(_shape('s1'));
      final unknown = _stored(
        UnknownObject({
          'id': 'u1',
          'pageId': _pageId,
          'type': 'x',
          'createdAt': 1,
          'updatedAt': 1,
        }),
      );
      final m = Affine2.scaling(2, 2);
      final r = resolve(
        TransformElements(
          pageId: _pageId,
          elementIds: [stroke.id, 't1', 's1', 'u1'],
          transform: m,
        ),
        _State({stroke.id: stroke}, {'t1': text, 's1': shape, 'u1': unknown}),
      );
      expect(r.edit.deltas, hasLength(3)); // the UnknownObject is skipped
      expect(fieldsOf(r, 't1'), {'frame', 'style'});
      expect(fieldsOf(r, 's1'), {'frame', 'geometry', 'style'});
      final t =
          r.edit.deltas.firstWhere((d) => d.id == 't1').after! as TextBoxObject;
      // The resolver result is the preview function's result, restamped.
      expect(t, text.transformed(m).copyWithMeta(updatedAt: _now, version: _v));
      final noWidth = resolve(
        TransformElements(
          pageId: _pageId,
          elementIds: ['s1'],
          transform: m,
          scaleStrokeWidth: false,
        ),
        _State({}, {'s1': shape}),
      );
      expect(fieldsOf(noWidth, 's1'), {'frame', 'geometry'});
      expect(
        resolve(
          TransformElements(
            pageId: _pageId,
            elementIds: ['t1'],
            transform: Affine2.identity,
          ),
          _State({}, {'t1': text}),
        ).edit.isEmpty,
        isTrue,
      );
    });
  });

  group('InsertPages / DuplicatePages copy objects', () {
    test('new ids, the new page, the original createdAt, normalized', () {
      final draft = PageDraft(
        size: PageSize.a4Portrait,
        background: const BlankBackground(),
        objects: [
          _shape(
            'x1',
            createdAt: 3,
          ).copyWith(style: const ShapeStyle(strokeColorArgb: 0x00FF0000)),
          _text('x2', createdAt: 4),
        ],
      );
      final r = resolve(
        InsertPages(drafts: [draft], position: const PageAtEnd()),
        _State({}, {}),
      );
      final objects = [
        for (final d in r.edit.deltas)
          if (d.after case final PageObject o) o,
      ];
      final newPage = r.edit.insertedPageIds.single;
      expect(objects.map((o) => o.pageId).toSet(), {newPage});
      expect(objects.map((o) => o.id), isNot(contains('x1')));
      expect(objects.map((o) => o.createdAt), [3, 4]);
      expect((objects.first as ShapeObject).style.strokeColorArgb, 0xFFFF0000);
      expect(objects.every((o) => o.version == _v), isTrue);
      expect(r.edit.insertedElementIds, containsAll(objects.map((o) => o.id)));

      final tooMany = PageDraft(
        size: PageSize.a4Portrait,
        background: const BlankBackground(),
        objects: [
          for (var i = 0; i <= PageObjectLimits.maxObjectsPerPage; i++)
            _shape('m$i'),
        ],
      );
      expect(
        () => resolve(
          InsertPages(drafts: [tooMany], position: const PageAtEnd()),
          _State({}, {}),
        ),
        throwsArgumentError,
      );
      final badLimit = PageDraft(
        size: PageSize.a4Portrait,
        background: const BlankBackground(),
        objects: [_text('big', text: 'x' * 10001)],
      );
      expect(
        () => resolve(
          InsertPages(drafts: [badLimit], position: const PageAtEnd()),
          _State({}, {}),
        ),
        throwsArgumentError,
      );
    });

    test('DuplicatePages copies the active objects', () {
      final o = _stored(_shape('o1', createdAt: 42));
      final r = resolve(
        const DuplicatePages(pageIds: [_pageId]),
        _State({stroke.id: stroke}, {'o1': o}),
      );
      final copy = r.edit.deltas
          .map((d) => d.after)
          .whereType<PageObject>()
          .single;
      expect(copy.id, isNot('o1'));
      expect(copy.pageId, r.edit.insertedPageIds.single);
      expect(copy.createdAt, 42);
      expect((copy as ShapeObject).geometry, o.geometry);
    });
  });

  group('sessions on the fake store', () {
    late NoteStore store;
    late NoteSession session;
    late PageId pageId;
    setUp(() async {
      store = createFakeNoteStore();
      final note = await store.library.createNote(title: 'objects');
      session = await store.openSession(note.id);
      pageId = session.pages.single.id;
      await session.openPage(pageId);
    });
    tearDown(() async {
      await session.close();
      await store.close();
    });

    ShapeObject shapeOn(String id) => ShapeObject(
      id: id,
      pageId: pageId,
      shapeKind: ShapeKind.line,
      geometry: ShapeGeometry.line(
        const PagePoint(0, 0),
        const PagePoint(10, 10),
      ),
      style: const ShapeStyle(strokeColorArgb: 0xFF000000),
      createdAt: 5,
    );

    test(
      'a failing composite changes nothing (memory, history, store)',
      () async {
        final before = session.pageIfLoaded(pageId)!;
        final history = session.history;
        expect(
          () => session.execute(
            CompositeCommand([
              AddStrokes(
                pageId: pageId,
                strokes: [
                  StrokeFixtures.synthetic(pageId: pageId, ids: store.ids),
                ],
              ),
              AddObjects(pageId: pageId, objects: [shapeOn('ok')]),
              AddObjects(pageId: pageId, objects: [shapeOn('ok')]),
            ]),
          ),
          throwsArgumentError,
        );
        expect(session.pageIfLoaded(pageId), same(before));
        expect(session.history, history);
        expect((await store.content.loadPage(pageId)).objects, isEmpty);
      },
    );

    test(
      'add → update → undo → undo → redo; unchanged objects keep identity',
      () async {
        await session
            .execute(
              AddObjects(pageId: pageId, objects: [shapeOn('a'), shapeOn('b')]),
            )
            .persisted;
        final afterAdd = session.pageIfLoaded(pageId)!;
        expect(afterAdd.objects.map((o) => o.id), ['a', 'b']);
        final b = afterAdd.objectById('b')!;
        final a = afterAdd.objectById('a')! as ShapeObject;
        await session
            .execute(
              UpdateObjects(
                pageId: pageId,
                objects: [a.copyWith(shapeKind: ShapeKind.arrow)],
              ),
            )
            .persisted;
        final afterUpdate = session.pageIfLoaded(pageId)!;
        expect(
          (afterUpdate.objectById('a')! as ShapeObject).shapeKind,
          ShapeKind.arrow,
        );
        expect(afterUpdate.objectById('b'), same(b), reason: 'K-4');
        expect(session.history.undoLabel, 'update-objects');
        await session.undo();
        expect(
          (session.pageIfLoaded(pageId)!.objectById('a')! as ShapeObject)
              .shapeKind,
          ShapeKind.line,
        );
        await session.undo();
        expect(session.pageIfLoaded(pageId)!.objects, isEmpty);
        await session.redo();
        expect(session.pageIfLoaded(pageId)!.objects.map((o) => o.id), [
          'a',
          'b',
        ]);
        await session.flush();
        expect(
          (await store.content.loadPage(pageId)).objects.map((o) => o.id),
          ['a', 'b'],
        );
      },
    );

    test(
      'a removed object id cannot be reused (one id space with strokes)',
      () async {
        await session
            .execute(AddObjects(pageId: pageId, objects: [shapeOn('gone')]))
            .persisted;
        await session
            .execute(RemoveElements(pageId: pageId, elementIds: ['gone']))
            .persisted;
        expect(
          () => session.execute(
            AddObjects(pageId: pageId, objects: [shapeOn('gone')]),
          ),
          throwsArgumentError,
        );
        final s = StrokeFixtures.synthetic(pageId: pageId, ids: store.ids);
        await session
            .execute(AddStrokes(pageId: pageId, strokes: [s]))
            .persisted;
        expect(
          () => session.execute(
            AddObjects(pageId: pageId, objects: [shapeOn(s.id)]),
          ),
          throwsArgumentError,
        );
      },
    );

    test('a stroke + object transform is one undo step', () async {
      final s = StrokeFixtures.synthetic(pageId: pageId, ids: store.ids);
      await session
          .execute(
            CompositeCommand([
              AddStrokes(pageId: pageId, strokes: [s]),
              AddObjects(pageId: pageId, objects: [shapeOn('t')]),
            ]),
          )
          .persisted;
      final depth = session.history.undoDepth;
      await session
          .execute(
            TransformElements(
              pageId: pageId,
              elementIds: [s.id, 't'],
              transform: Affine2.translation(5, 5),
            ),
          )
          .persisted;
      expect(session.history.undoDepth, depth + 1);
      await session.undo();
      final content = session.pageIfLoaded(pageId)!;
      expect(
        (content.objectById('t')! as ShapeObject).geometry,
        shapeOn('t').geometry,
      );
      expect(content.strokeById(s.id)!.points.contentEquals(s.points), isTrue);
    });
  });
}
