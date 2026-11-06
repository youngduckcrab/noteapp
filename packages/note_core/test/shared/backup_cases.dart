// Shared cases of NoteStore.exportBackupJson (CORE 6.17, T19), run on the SQLite store
// (test/backup/backup_export_test.dart), the fake (test/testing/fake_backup_export_test.dart)
// and in Chrome (test/web/backup_export_browser_test.dart). Web-safe (no dart:io).
//
// The golden state (v2 — m5-7/02-core 6.14.4): folders 2, notes 3 (one in the trash),
// pages 4, strokes 20 (one erased, one linked to the recording), presets 5, assets 3 (pdf,
// audio, image), settings 2 (one reset), a recording with a title, page objects of the 5
// types (shape, text box, image, math, an unknown type) and a handwriting result. Whole-entity
// versions only (the fake keeps no per-field versions), so both stores export the same bytes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/fake/fake_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

const int kBackupT = 1793750400000; // 2026-11-04T00:00:00Z
const String kBackupNode = '0000000000000001'; // the fake's device node
final Clock kBackupClock = Clock.fixed(
  DateTime.fromMillisecondsSinceEpoch(kBackupT + 86400000, isUtc: true),
);

Hlc _v(int i) => Hlc(kBackupT + i, 0, '00000000000000c1');

/// The golden state with its versions (entity.version == versions.max).
List<VersionedEntity> backupGoldenState() {
  var i = 0;
  VersionedEntity v(SyncEntity Function(Hlc v) build) {
    final version = _v(++i);
    return VersionedEntity(build(version), EntityFieldVersions(version));
  }

  final ids = SequentialIdGenerator(prefix: 'gen');
  Stroke stroke(int n, PageId pageId, Hlc version) {
    final s = StrokeFixtures.synthetic(
      pageId: pageId,
      ids: ids,
      seed: n,
      pointCount: 6,
      createdAt: kBackupT + n,
    );
    return Stroke(
      id: 'stk-${n.toString().padLeft(2, '0')}',
      pageId: pageId,
      style: s.style,
      points: s.points,
      recordingId: n == 0 ? 'rec-a' : null,
      recordingOffsetMs: n == 0 ? 1500 : null,
      createdAt: s.createdAt,
      // Not after its note: applyRemote raises Note.updatedAt to the max (6.10.3).
      updatedAt: kBackupT,
      deletedAt: n == 19 ? kBackupT + 500 : null,
      version: version,
    );
  }

  Page page(String id, NoteId noteId, String sortKey, Hlc version) => Page(
    id: id,
    noteId: noteId,
    sortKey: sortKey,
    size: PageSize.a4Portrait,
    background: const BlankBackground(),
    createdAt: kBackupT,
    updatedAt: kBackupT,
    version: version,
  );

  final strokePages = [
    for (var n = 0; n < 20; n++)
      n < 10
          ? 'page-a1'
          : n < 15
          ? 'page-a2'
          : n < 18
          ? 'page-b1'
          : 'page-c1',
  ];
  return [
    v(
      (x) => Folder(
        id: 'fld-a',
        ownerId: kLocalOwnerId,
        name: '수업',
        sortKey: 'a0',
        createdAt: kBackupT,
        updatedAt: kBackupT,
        version: x,
      ),
    ),
    v(
      (x) => Folder(
        id: 'fld-b',
        ownerId: kLocalOwnerId,
        parentId: 'fld-a',
        name: '수학',
        colorArgb: 0xFF3366FF,
        sortKey: 'a0',
        createdAt: kBackupT,
        updatedAt: kBackupT,
        version: x,
      ),
    ),
    v(
      (x) => Note(
        id: 'note-a',
        ownerId: kLocalOwnerId,
        folderId: 'fld-b',
        title: '미적분 정리',
        tags: const ['math', '2학기'],
        isFavorite: true,
        sortKey: 'a0',
        createdAt: kBackupT,
        updatedAt: kBackupT + 10,
        version: x,
      ),
    ),
    v(
      (x) => Note(
        id: 'note-b',
        ownerId: kLocalOwnerId,
        title: 'Quick notes',
        cover: const ColorCover(0xFFFFCC00),
        sortKey: 'a1',
        createdAt: kBackupT,
        updatedAt: kBackupT,
        version: x,
      ),
    ),
    v(
      (x) => Note(
        id: 'note-c',
        ownerId: kLocalOwnerId,
        title: 'Old draft',
        sortKey: 'a2',
        createdAt: kBackupT,
        updatedAt: kBackupT + 100,
        deletedAt: kBackupT + 100,
        trashRootId: 'note-c',
        version: x,
      ),
    ),
    v((x) => page('page-a1', 'note-a', 'a0', x)),
    v((x) => page('page-a2', 'note-a', 'a1', x)),
    v((x) => page('page-b1', 'note-b', 'a0', x)),
    v((x) => page('page-c1', 'note-c', 'a0', x)),
    for (var n = 0; n < 20; n++) v((x) => stroke(n, strokePages[n], x)),
    for (var n = 0; n < 5; n++)
      v(
        (x) => PenPreset(
          id: 'pre-$n',
          ownerId: kLocalOwnerId,
          name: '펜 $n',
          style: StrokeStyle.defaultsFor(
            PenTool.values[n % PenTool.values.length],
          ),
          sortKey: 'a$n',
          createdAt: kBackupT,
          updatedAt: kBackupT,
          version: x,
        ),
      ),
    v(
      (x) => Asset(
        id: 'e' * 64,
        ownerId: kLocalOwnerId,
        type: AssetType.pdf,
        mimeType: 'application/pdf',
        size: 1234,
        fileName: '교재.pdf',
        createdAt: kBackupT,
        storagePath: 'users/u/assets/${'e' * 64}',
        hasLocalBytes: true,
        version: x,
      ),
    ),
    v(
      (x) => SettingValue(
        key: 'editor.palette',
        valueJson: '["#000000","#3366ff"]',
        updatedAt: kBackupT,
        version: x,
      ),
    ),
    v(
      (x) => SettingValue(
        key: 'library.sortField',
        valueJson: '"name"',
        updatedAt: kBackupT,
        deletedAt: kBackupT + 7,
        version: x,
      ),
    ),
    // (v2.0) the new kinds and the recording title.
    v(
      (x) => Asset(
        id: 'a' * 64,
        ownerId: kLocalOwnerId,
        type: AssetType.audio,
        mimeType: 'audio/mp4',
        size: 4096,
        createdAt: kBackupT,
        version: x,
      ),
    ),
    v(
      (x) => Asset(
        id: 'b' * 64,
        ownerId: kLocalOwnerId,
        type: AssetType.image,
        mimeType: 'image/png',
        size: 2048,
        fileName: '그림.png',
        createdAt: kBackupT,
        version: x,
      ),
    ),
    v(
      (x) => Recording(
        id: 'rec-a',
        noteId: 'note-a',
        assetId: 'a' * 64,
        durationMs: 65000,
        startedAt: kBackupT - 60000,
        createdAt: kBackupT,
        updatedAt: kBackupT,
        title: '1교시 강의',
        version: x,
      ),
    ),
    for (final o in <PageObject>[
      PageObjectFixtures.shape(
        id: 'obj-1',
        pageId: 'page-a1',
        kind: ShapeKind.star,
        createdAt: kBackupT + 1,
      ),
      PageObjectFixtures.textBox(
        id: 'obj-2',
        pageId: 'page-a1',
        text: '극한의 정의',
        createdAt: kBackupT + 2,
      ),
      PageObjectFixtures.image(
        id: 'obj-3',
        pageId: 'page-a1',
        assetId: 'b' * 64,
        createdAt: kBackupT + 3,
      ),
      PageObjectFixtures.math(
        id: 'obj-4',
        pageId: 'page-b1',
        latex: r'\lim_{x \to 0} \frac{\sin x}{x} = 1',
        createdAt: kBackupT + 4,
      ),
      PageObjectFixtures.unknown(id: 'obj-5', pageId: 'page-b1'),
    ])
      v((x) => o.copyWithMeta(updatedAt: kBackupT, version: x)),
    v(
      (x) => HandwritingText(
        noteId: 'note-a',
        pageId: 'page-a1',
        engineId: 'mlkit-digital-ink/19.0.0:ko',
        sourceRev: '0123456789abcdef:ko',
        lines: const [
          HandwritingLine(
            text: '미분 정의',
            alternatives: ['미분 정이'],
            rect: PageRect(40, 60, 320, 110),
            strokeIds: ['stk-00', 'stk-01'],
            languageTag: 'ko',
          ),
        ],
        createdAt: kBackupT,
        version: x,
      ),
    ),
  ];
}

/// The fake has no remote path: [state] goes straight into its tables.
Future<void> seedFakeBackupState(
  NoteStore store,
  List<VersionedEntity> state,
) async {
  final fake = store as FakeNoteStore;
  for (final VersionedEntity(:entity) in state) {
    switch (entity) {
      case Folder():
        fake.folders[entity.id] = entity;
      case Note():
        fake.notes[entity.id] = entity;
      case Page():
        fake.pages[entity.id] = entity;
      case Stroke():
        fake.strokes[entity.id] = entity;
        (fake.strokesOfPage[entity.pageId] ??= {}).add(entity.id);
      case PenPreset():
        fake.presets[entity.id] = entity;
      case Asset():
        fake.assetRows[entity.id] = entity;
      case SettingValue():
        fake.syncedSettings[entity.key] = entity;
      case Recording():
        fake.recordingRows[entity.id] = entity;
      case PageObject():
        fake.putObject(entity);
      case HandwritingText():
        fake.handwritingRows[entity.pageId] = entity;
      default:
        throw UnsupportedError('${entity.kind} is not in the fake');
    }
  }
}

/// A fake store for [defineBackupTests] (no default presets, [kBackupClock]).
Future<NoteStore> openFakeBackupStore() async =>
    createFakeNoteStore(clock: kBackupClock, seedDefaultPenPresets: false);

/// A device-scope setting: never in the backup.
final SettingKey<bool> kDeviceOnlySetting = SettingKey.boolean(
  'editor.backupTestDeviceOnly',
  false,
  scope: SettingScope.device,
);

Map<String, Object?> _parse(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

List<Map<String, Object?>> _entities(Map<String, Object?> doc) => [
  for (final e in doc['entities']! as List<Object?>) e! as Map<String, Object?>,
];

/// Entities per kind name in [doc].
Map<String, int> _kindCounts(Map<String, Object?> doc) {
  final counts = <String, int>{};
  for (final e in _entities(doc)) {
    counts.update(e['kind']! as String, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// The PDF asset of the golden state (its search owner is device-local).
const String _backupPdfAsset =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

/// [open] returns a fresh store on [kBackupClock] (no default presets, device node
/// [kBackupNode]); [seed] writes the golden state into it.
void defineBackupTests({
  required Future<NoteStore> Function() open,
  required Future<void> Function(NoteStore store, List<VersionedEntity> state)
  seed,
}) {
  group('exportBackupJson (6.17)', () {
    late NoteStore store;
    late List<VersionedEntity> state;

    setUp(() async {
      store = await open();
      state = backupGoldenState();
      await seed(store, state);
    });
    tearDown(() => store.close());

    test('header: format, version, time, owner, device, schema', () async {
      final doc = _parse(await store.exportBackupJson());
      expect(doc.keys.toList(), [
        'format',
        'formatVersion',
        'exportedAt',
        'ownerId',
        'deviceNodeId',
        'schema',
        'entities',
      ]);
      expect(doc['format'], 'noteapp-backup');
      expect(doc['formatVersion'], 1);
      expect(doc['exportedAt'], kBackupClock.now().millisecondsSinceEpoch);
      expect(doc['ownerId'], kLocalOwnerId);
      expect(doc['deviceNodeId'], kBackupNode);
      expect(doc['schema'], {
        'note': kNoteSchemaVersion,
        'database': kDatabaseSchemaVersion,
        'strokePoints': kStrokePointsFormatVersion,
      });
    });

    test('every entity of the state round-trips, the trash included', () async {
      final entities = _entities(_parse(await store.exportBackupJson()));
      final counts = <String, int>{};
      for (final e in entities) {
        counts.update(e['kind']! as String, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(counts, {
        'folder': 2,
        'note': 3,
        'page': 4,
        'stroke': 20,
        'penPreset': 5,
        'asset': 3,
        'recording': 1,
        'setting': 2,
        'pageObject': 5,
        'handwriting': 1,
      });
      final want = {
        for (final v in state) '${v.entity.kind.name}/${v.entity.id}': v,
      };
      for (final e in entities) {
        final kind = EntityKind.values.byName(e['kind']! as String);
        final data = e['data']! as Map<String, Object?>;
        final decoded = EntityJson.decode(kind, data);
        final expected = want['${kind.name}/${decoded.id}']!;
        expect(decoded.toJson(), expected.entity.toJson(), reason: decoded.id);
        final versions = EntityFieldVersions.fromJson(
          e['versions']! as Map<String, Object?>,
        );
        expect(versions.toJson(), expected.versions.toJson());
        expect(decoded.version, versions.max);
      }
      final trashed = entities.firstWhere(
        (e) => (e['data']! as Map<String, Object?>)['id'] == 'note-c',
      );
      expect(
        (trashed['data']! as Map<String, Object?>)['deletedAt'],
        isNotNull,
      );
    });

    test('no asset bytes, local fields, device settings or meta', () async {
      await store.settings.set(kDeviceOnlySetting, true);
      final text = utf8.decode(await store.exportBackupJson());
      for (final local in [
        'hasLocalBytes',
        'pageCount',
        'firstPageId',
        'lastOpenedAt',
        'contentRevision',
        'backupTestDeviceOnly',
      ]) {
        expect(text, isNot(contains(local)), reason: local);
      }
      final assets = _entities(jsonDecode(text) as Map<String, Object?>)
          .where((e) => e['kind'] == 'asset');
      expect(assets, hasLength(3));
      for (final asset in assets) {
        expect(
          (asset['data']! as Map<String, Object?>).keys,
          isNot(contains('bytes')),
        );
      }
    });

    test('deterministic: kind then id order, the same bytes twice', () async {
      final first = await store.exportBackupJson();
      final second = await store.exportBackupJson();
      expect(second, first);
      final keys = [
        for (final e in _entities(_parse(first)))
          (
            EntityKind.values.byName(e['kind']! as String).index,
            (e['data']! as Map<String, Object?>)['id'] ??
                (e['data']! as Map<String, Object?>)['key'],
          ),
      ];
      final sorted = [...keys]
        ..sort((a, b) {
          final k = a.$1.compareTo(b.$1);
          return k != 0 ? k : (a.$2! as String).compareTo(b.$2! as String);
        });
      expect(keys, sorted);
    });

    test('(v2.0) no search index, recording drafts, page caches or derived '
        'columns (m5-7/02-core 6.14.4)', () async {
      final before = _kindCounts(_parse(await store.exportBackupJson()));
      final note = await store.library.createNote(
        title: '색인 노트',
        pages: [
          PageDraft(
            size: PageSize.a4Portrait,
            background: const PdfBackground(
              assetId: _backupPdfAsset,
              pdfPageIndex: 0,
            ),
            objects: [PageObjectFixtures.textBox(pageId: 'x', text: '상자 글자')],
          ),
        ],
      );
      await store.search.replaceUnits(
        SearchSource.pdf,
        '$_backupPdfAsset#0',
        const [SearchUnitDraft(body: '교재에만 있는 낱말')],
        sourceRev: 'pdf-rev-1',
      );
      final draft = await store.recordingDrafts.begin(
        recordingId: store.ids.newId(),
        noteId: note.id,
        mimeType: 'audio/webm',
        startedAt: kBackupT,
      );
      await store.recordingDrafts.append(
        draft.draftId,
        Uint8List.fromList(utf8.encode('draft-chunk-bytes')),
        activeMs: 10,
      );
      // Fills the page caches of the SQLite store (pages.ink_rev).
      expect(await store.handwriting.stalePages(note.id), isEmpty);
      expect(await store.search.searchPages('교재에만'), hasLength(1));
      expect(await store.search.searchPages('상자 글자'), hasLength(1));

      final doc = _parse(await store.exportBackupJson());
      final text = jsonEncode(doc);
      for (final local in [
        '교재에만 있는 낱말',
        'pdf-rev-1',
        draft.draftId,
        'draft-chunk-bytes',
        'audio/webm',
        'inkRev',
        'bgAssetId',
        'bgPdfPageIndex',
        'nameNorm',
        'titleNorm',
      ]) {
        expect(text, isNot(contains(local)), reason: local);
      }
      // Only the new note's entities were added: the note, its page and the text box.
      final after = _kindCounts(doc);
      expect(
        {
          for (final k in after.keys)
            if (after[k] != before[k]) k: after[k]! - (before[k] ?? 0),
        },
        {'note': 1, 'page': 1, 'pageObject': 1},
      );
      expect(text, contains('상자 글자'), reason: 'the object itself is data');
    });

    test('later edits are in the next export', () async {
      final before = _entities(_parse(await store.exportBackupJson())).length;
      await store.library.createFolder(name: 'new');
      final after = _entities(_parse(await store.exportBackupJson())).length;
      expect(after, before + 1);
    });
  });
}
