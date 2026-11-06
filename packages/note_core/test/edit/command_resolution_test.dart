// CORE 6.5: every EditCommand → AppliedEdit deltas and changed fields (8.1 T5).
import 'package:note_core/note_core.dart';
import 'package:note_core/src/edit/command_resolver.dart';
import 'package:note_core/src/sync/outbox_types.dart' as outbox;
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

const _now = 5000;
const _v = Hlc(5000, 0, '0000000000000001');

final class _State implements ResolveState {
  _State(this.pages, this.loaded);
  final List<Page> pages;
  final Map<PageId, Map<ElementId, Stroke>> loaded;

  @override
  NoteId get noteId => 'n1';
  @override
  List<Page> get activePages => pages.where((p) => !p.isDeleted).toList();
  @override
  Page? knownPage(PageId id) => pages.where((p) => p.id == id).firstOrNull;
  @override
  Map<ElementId, Stroke>? activeStrokes(PageId pageId) => loaded[pageId];
  @override
  Map<ElementId, PageObject>? activeObjects(PageId pageId) =>
      loaded.containsKey(pageId) ? const {} : null;
  @override
  bool isKnownStroke(ElementId id) => false;
  @override
  bool isKnownObject(ElementId id) => false;
}

Page _page(String id, String key) => Page(
  id: id,
  noteId: 'n1',
  sortKey: key,
  size: PageSize.a4Portrait,
  background: const BlankBackground(),
  createdAt: 0,
  updatedAt: 0,
  version: const Hlc(1, 0, '0000000000000001'),
);

void main() {
  late SequentialIdGenerator ids;
  late List<Stroke> strokes;
  late _State state;
  late CommandResolver resolver;

  ResolvedEdit resolve(EditCommand c) =>
      resolver.resolve(c, state, now: _now, version: _v);

  Set<String> fieldsOf(
    ResolvedEdit r,
    String id, [
    EntityKind kind = EntityKind.stroke,
  ]) => r.changedFields[outbox.EntityRef(kind, id)]!;

  setUp(() {
    ids = SequentialIdGenerator(prefix: 'new');
    final fixtureIds = SequentialIdGenerator(prefix: 's');
    strokes = [
      for (var i = 0; i < 5; i++)
        StrokeFixtures.synthetic(
          pageId: 'p1',
          ids: fixtureIds,
          seed: i,
          createdAt: 100 + i,
          tool: i == 4 ? PenTool.highlighter : PenTool.ballpoint,
        ).copyWith(version: const Hlc(1, 0, '0000000000000001')),
    ];
    state = _State(
      [_page('p1', 'a0'), _page('p2', 'a1'), _page('p3', 'a2')],
      {
        'p1': {for (final s in strokes) s.id: s},
        'p2': {},
      },
    );
    resolver = CommandResolver(ids: ids);
  });

  test(
    'AddStrokes: created with version + updatedAt, style normalized, fields *',
    () {
      final s = StrokeFixtures.synthetic(pageId: 'p2', ids: ids, seed: 9)
          .copyWith(
            style: const StrokeStyle(
              tool: PenTool.pencil,
              colorArgb: 0x80112233,
              width: 99,
            ),
          );
      final r = resolve(AddStrokes(pageId: 'p2', strokes: [s]));
      final d = r.edit.deltas.single;
      expect(d.before, isNull);
      final after = d.after! as Stroke;
      expect(after.version, _v);
      expect(after.updatedAt, _now);
      expect(after.createdAt, s.createdAt);
      expect(after.style.colorArgb, 0xFF112233);
      expect(after.style.width, 30);
      expect(fieldsOf(r, s.id), {'*'});
      expect(r.edit.insertedElementIds, [s.id]);
      expect(r.edit.affectedPageIds, {'p2'});
      expect(r.edit.version, _v);
    },
  );

  test('AddStrokes argument errors', () {
    final s = StrokeFixtures.synthetic(pageId: 'p2', ids: ids);
    expect(
      () => resolve(AddStrokes(pageId: 'p1', strokes: [s])),
      throwsArgumentError,
    );
    expect(
      () => resolve(
        AddStrokes(
          pageId: 'p2',
          strokes: [s.copyWith(version: _v)],
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => resolve(AddStrokes(pageId: 'p2', strokes: [s, s])),
      throwsArgumentError,
    );
    expect(
      () => resolve(AddStrokes(pageId: 'p1', strokes: [strokes[0].copyWith()])),
      throwsArgumentError,
      reason: 'id already exists',
    );
    expect(
      () => resolve(
        AddStrokes(
          pageId: 'p2',
          strokes: [s.copyWith(id: 'bad id')],
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => resolve(
        AddStrokes(
          pageId: 'p3',
          strokes: [s.copyWith(pageId: 'p3')],
        ),
      ),
      throwsA(isA<PageNotOpenException>()),
    );
  });

  test('RemoveStrokes: {deletedAt}; unknown ids ignored', () {
    final r = resolve(
      RemoveStrokes(pageId: 'p1', strokeIds: [strokes[0].id, 'nope']),
    );
    expect(r.edit.deltas, hasLength(1));
    final d = r.edit.deltas.single;
    expect(d.before, strokes[0]);
    expect((d.after! as Stroke).deletedAt, _now);
    expect(fieldsOf(r, strokes[0].id), {'deletedAt'});
    expect(
      resolve(const RemoveStrokes(pageId: 'p1', strokeIds: ['nope']))
          .edit
          .isEmpty,
      isTrue,
    );
  });

  test('SplitStrokes: 5 strokes → 7 fragments, one edit', () {
    final fragments = <Stroke>[
      for (final s in strokes)
        s.fragment(id: ids.newId(), points: s.points.sublist(0, 10)),
      strokes[0].fragment(
        id: ids.newId(),
        points: strokes[0].points.sublist(50),
      ),
      strokes[1].fragment(
        id: ids.newId(),
        points: strokes[1].points.sublist(60),
      ),
    ];
    final r = resolve(
      SplitStrokes(
        pageId: 'p1',
        removedIds: [for (final s in strokes) s.id],
        added: fragments,
      ),
    );
    expect(r.edit.deltas, hasLength(12));
    final removed = r.edit.deltas.where((d) => d.before != null).toList();
    final added = r.edit.deltas.where((d) => d.before == null).toList();
    expect(removed, hasLength(5));
    expect(added, hasLength(7));
    for (final d in removed) {
      expect(fieldsOf(r, d.id), {'deletedAt'});
    }
    for (final d in added) {
      final f = d.after! as Stroke;
      final source = strokes.firstWhere((s) => s.createdAt == f.createdAt);
      expect(fieldsOf(r, d.id), {'*'});
      expect(f.style, source.style);
      expect(
        f.points.t(0),
        anyOf(source.points.t(0), source.points.t(50), source.points.t(60)),
      );
    }
    expect(r.edit.insertedElementIds, [for (final f in fragments) f.id]);
  });

  test('TransformElements: {points} (+ style when the width changes)', () {
    final move = resolve(
      TransformElements(
        pageId: 'p1',
        elementIds: [strokes[0].id],
        transform: Affine2.translation(5, 0),
      ),
    );
    expect(fieldsOf(move, strokes[0].id), {'points'});
    final after = move.edit.deltas.single.after! as Stroke;
    expect(after.points.x(0), closeTo(strokes[0].points.x(0) + 5, 0.011));
    expect(after.id, strokes[0].id);
    final scale = resolve(
      TransformElements(
        pageId: 'p1',
        elementIds: [strokes[1].id],
        transform: Affine2.scaling(2, 2),
      ),
    );
    expect(fieldsOf(scale, strokes[1].id), {'points', 'style'});
    expect(
      resolve(
        TransformElements(
          pageId: 'p1',
          elementIds: [strokes[0].id],
          transform: Affine2.identity,
        ),
      ).edit.isEmpty,
      isTrue,
    );
  });

  test('RestyleStrokes: {style}; empty patch / same style → empty edit', () {
    final r = resolve(
      RestyleStrokes(
        pageId: 'p1',
        strokeIds: [strokes[0].id],
        patch: const StrokeStylePatch(colorArgb: 0xFFFF0000),
      ),
    );
    expect(fieldsOf(r, strokes[0].id), {'style'});
    expect((r.edit.deltas.single.after! as Stroke).style.colorArgb, 0xFFFF0000);
    expect(
      resolve(
        RestyleStrokes(
          pageId: 'p1',
          strokeIds: [strokes[0].id],
          patch: const StrokeStylePatch(),
        ),
      ).edit.isEmpty,
      isTrue,
    );
    expect(
      resolve(
        RestyleStrokes(
          pageId: 'p1',
          strokeIds: [strokes[0].id],
          patch: StrokeStylePatch(colorArgb: strokes[0].style.colorArgb),
        ),
      ).edit.isEmpty,
      isTrue,
    );
  });

  test('ClearPage with the highlighter filters', () {
    final all = resolve(const ClearPage(pageId: 'p1'));
    expect(all.edit.deltas, hasLength(5));
    final hl = resolve(
      const ClearPage(pageId: 'p1', filter: StrokeFilter.highlighterOnly),
    );
    expect(hl.edit.deltas.map((d) => d.id), [strokes[4].id]);
    final rest = resolve(
      const ClearPage(pageId: 'p1', filter: StrokeFilter.exceptHighlighter),
    );
    expect(rest.edit.deltas, hasLength(4));
    expect(fieldsOf(rest, strokes[0].id), {'deletedAt'});
  });

  test(
    'InsertPages: new sortKeys, draft strokes get new ids, createdAt kept',
    () {
      final draftStroke = strokes[0].copyWith();
      final r = resolve(
        InsertPages(
          drafts: [
            PageDraft(
              size: PageSize.letterPortrait,
              background: const BlankBackground(),
              strokes: [draftStroke],
            ),
            PageDraft.blankA4,
          ],
          position: const PageAfter('p1'),
        ),
      );
      final pages = [
        for (final d in r.edit.deltas)
          if (d.after case final Page p) p,
      ];
      expect(pages, hasLength(2));
      expect(r.edit.insertedPageIds, [for (final p in pages) p.id]);
      expect(pages[0].sortKey.compareTo('a0'), greaterThan(0));
      expect(pages[1].sortKey.compareTo('a1'), lessThan(0));
      expect(pages[0].sortKey.compareTo(pages[1].sortKey), lessThan(0));
      final copy = r.edit.deltas.map((d) => d.after).whereType<Stroke>().single;
      expect(copy.id, isNot(draftStroke.id));
      expect(copy.pageId, pages[0].id);
      expect(copy.createdAt, draftStroke.createdAt);
      expect(fieldsOf(r, pages[0].id, EntityKind.page), {'*'});
      expect(
        () => resolve(const InsertPages(drafts: [], position: PageAtEnd())),
        throwsArgumentError,
      );
      expect(
        () => resolve(
          const InsertPages(
            drafts: [PageDraft.blankA4],
            position: PageBefore('nope'),
          ),
        ),
        throwsArgumentError,
      );
      final start = resolve(
        const InsertPages(drafts: [PageDraft.blankA4], position: PageAtStart()),
      );
      expect(
        (start.edit.deltas.single.after! as Page).sortKey.compareTo('a0'),
        lessThan(0),
      );
    },
  );

  test('DeletePages: {deletedAt}; the last page cannot go', () {
    final r = resolve(const DeletePages(pageIds: ['p2', 'p3']));
    expect(r.edit.deltas, hasLength(2));
    expect(fieldsOf(r, 'p2', EntityKind.page), {'deletedAt'});
    expect(
      () => resolve(const DeletePages(pageIds: ['p1', 'p2', 'p3'])),
      throwsA(isA<LastPageDeletionException>()),
    );
  });

  test('DuplicatePages: copy right after its source, strokes copied', () {
    final r = resolve(const DuplicatePages(pageIds: ['p1']));
    final page = r.edit.deltas.map((d) => d.after).whereType<Page>().single;
    expect(page.sortKey.compareTo('a0'), greaterThan(0));
    expect(page.sortKey.compareTo('a1'), lessThan(0));
    final copies = r.edit.deltas
        .map((d) => d.after)
        .whereType<Stroke>()
        .toList();
    expect(copies, hasLength(5));
    expect(copies.map((s) => s.createdAt), [
      for (final s in strokes) s.createdAt,
    ]);
    expect(
      () => resolve(const DuplicatePages(pageIds: ['p3'])),
      throwsA(isA<PageNotOpenException>()),
    );
  });

  test('MovePages: {sortKey}, relative order kept', () {
    final r = resolve(
      const MovePages(pageIds: ['p3', 'p2'], position: PageAtStart()),
    );
    final moved = {
      for (final d in r.edit.deltas) d.id: (d.after! as Page).sortKey,
    };
    expect(moved.keys.toSet(), {'p2', 'p3'});
    expect(moved['p2']!.compareTo(moved['p3']!), lessThan(0));
    expect(moved['p3']!.compareTo('a0'), lessThan(0));
    expect(fieldsOf(r, 'p2', EntityKind.page), {'sortKey'});
    expect(
      () =>
          resolve(const MovePages(pageIds: ['p2'], position: PageAfter('p2'))),
      throwsArgumentError,
    );
  });

  test('SetPageBackground: {background}, unchanged pages skipped', () {
    const bg = TemplateBackground(
      template: PageTemplate(kind: PageTemplateKind.grid),
    );
    final r = resolve(
      const SetPageBackground(pageIds: ['p1', 'p2'], background: bg),
    );
    expect(r.edit.deltas, hasLength(2));
    expect(fieldsOf(r, 'p1', EntityKind.page), {'background'});
    expect(
      resolve(
        const SetPageBackground(pageIds: ['p1'], background: BlankBackground()),
      ).edit.isEmpty,
      isTrue,
    );
  });

  test('ResizePages: {size}, clamped', () {
    final r = resolve(
      const ResizePages(pageIds: ['p1'], size: PageSize(10, 99999)),
    );
    expect(
      (r.edit.deltas.single.after! as Page).size,
      const PageSize(72, 14400),
    );
    expect(fieldsOf(r, 'p1', EntityKind.page), {'size'});
  });

  test('CompositeCommand: first before, last after, union of fields', () {
    final r = resolve(
      CompositeCommand([
        TransformElements(
          pageId: 'p1',
          elementIds: [strokes[0].id],
          transform: Affine2.translation(1, 1),
        ),
        RestyleStrokes(
          pageId: 'p1',
          strokeIds: [strokes[0].id],
          patch: const StrokeStylePatch(colorArgb: 0xFF00FF00),
        ),
      ], label: 'paste'),
    );
    expect(r.edit.label, 'paste');
    final d = r.edit.deltas.single;
    expect(d.before, strokes[0]);
    final after = d.after! as Stroke;
    expect(after.style.colorArgb, 0xFF00FF00);
    expect(after.points.x(0), closeTo(strokes[0].points.x(0) + 1, 0.011));
    expect(fieldsOf(r, strokes[0].id), {'points', 'style'});

    // Insert a page and draw on it in one edit (paste into a new page).
    final pageId = 'p-new';
    final s = StrokeFixtures.synthetic(pageId: pageId, ids: ids);
    final paste = resolve(
      CompositeCommand([
        InsertPages(
          drafts: [
            PageDraft(
              id: pageId,
              size: PageSize.a4Portrait,
              background: const BlankBackground(),
            ),
          ],
          position: const PageAtEnd(),
        ),
        AddStrokes(pageId: pageId, strokes: [s]),
      ]),
    );
    expect(paste.edit.insertedPageIds, [pageId]);
    expect(paste.edit.insertedElementIds, [s.id]);
  });

  test('every command label', () {
    expect(
      [
        const AddStrokes(pageId: 'p', strokes: []).label,
        const RemoveStrokes(pageId: 'p', strokeIds: []).label,
        const SplitStrokes(pageId: 'p', removedIds: [], added: []).label,
        const TransformElements(
          pageId: 'p',
          elementIds: [],
          transform: Affine2.identity,
        ).label,
        const RestyleStrokes(
          pageId: 'p',
          strokeIds: [],
          patch: StrokeStylePatch(),
        ).label,
        const ClearPage(pageId: 'p').label,
        const InsertPages(drafts: [], position: PageAtEnd()).label,
        const DeletePages(pageIds: []).label,
        const DuplicatePages(pageIds: []).label,
        const MovePages(pageIds: [], position: PageAtEnd()).label,
        const SetPageBackground(
          pageIds: [],
          background: BlankBackground(),
        ).label,
        const ResizePages(pageIds: [], size: PageSize.a4Portrait).label,
        const CompositeCommand([]).label,
      ],
      [
        'add-strokes',
        'remove-strokes',
        'split-strokes',
        'transform',
        'restyle',
        'clear-page',
        'insert-pages',
        'delete-pages',
        'duplicate-pages',
        'move-pages',
        'set-background',
        'resize-pages',
        'composite',
      ],
    );
  });
}
