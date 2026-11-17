import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';

Map<String, Object?> _without(Map<String, Object?> m, String key) =>
    Map.of(m)..remove(key);

void main() {
  test('every sample entity round-trips through EntityJson.decode', () {
    for (final e in kSampleEntities.entries) {
      final entity = e.value;
      final back = EntityJson.decode(entity.kind, entity.toJson());
      expect(back.toJson(), entity.toJson(), reason: e.key);
      expect(back.kind, entity.kind);
      expect(back.id, entity.id);
      expect(back.version, entity.version);
      expect(back.isDeleted, entity.isDeleted);
    }
  });

  test('every kind is covered by the samples (21 entity shapes)', () {
    expect(
      kSampleEntities.values.map((e) => e.kind).toSet(),
      EntityKind.values.toSet(),
    );
    expect(kSampleEntities.length, 21);
  });

  test('local-only fields are not serialized and get fixed values', () {
    final note = kSampleEntities['note']! as Note;
    final json = note.toJson();
    for (final k in ['pageCount', 'firstPageId', 'lastOpenedAt']) {
      expect(json.containsKey(k), isFalse, reason: k);
    }
    final back = Note.fromJson(json);
    expect(back.pageCount, 0);
    expect(back.firstPageId, isNull);
    expect(back.lastOpenedAt, isNull);

    final page = kSampleEntities['page_blank']! as Page;
    expect(page.toJson().containsKey('contentRevision'), isFalse);
    expect(Page.fromJson(page.toJson()).contentRevision, 0);

    final asset = kSampleEntities['asset']! as Asset;
    expect(asset.hasLocalBytes, isTrue);
    expect(asset.toJson().containsKey('hasLocalBytes'), isFalse);
    expect(Asset.fromJson(asset.toJson()).hasLocalBytes, isFalse);

    final stroke = kSampleEntities['stroke']! as Stroke;
    expect(stroke.toJson().containsKey('bounds'), isFalse);
  });

  test('unknown keys are ignored (an UnknownObject keeps them — C-12)', () {
    for (final e in kSampleEntities.values) {
      final json = {
        ...e.toJson(),
        'futureField': 42,
        'nested': {'x': 1},
      };
      expect(
        EntityJson.decode(e.kind, json).toJson(),
        e is UnknownObject ? json : e.toJson(),
      );
    }
  });

  test('a missing required key or a wrong type is a FormatException', () {
    final required = <String, List<String>>{
      'folder': ['id', 'ownerId', 'name', 'sortKey', 'createdAt', 'updatedAt'],
      'note': ['id', 'ownerId', 'title', 'sortKey', 'createdAt', 'updatedAt'],
      'page_blank': [
        'id',
        'noteId',
        'sortKey',
        'size',
        'background',
        'createdAt',
        'updatedAt',
      ],
      'stroke': ['id', 'pageId', 'style', 'points', 'createdAt', 'updatedAt'],
      'pen_preset': [
        'id',
        'ownerId',
        'name',
        'style',
        'sortKey',
        'createdAt',
        'updatedAt',
      ],
      'asset': ['id', 'ownerId', 'type', 'mimeType', 'size', 'createdAt'],
      'recording': [
        'id',
        'noteId',
        'assetId',
        'durationMs',
        'startedAt',
        'createdAt',
        'updatedAt',
      ],
      'setting': ['key', 'valueJson', 'updatedAt'],
      // (v2.0, m5-7/02-core 6.2.6) known object types; `frame` is ignored for shapes.
      'shape_rect': [
        'id',
        'pageId',
        'type',
        'shape',
        'geometry',
        'style',
        'createdAt',
        'updatedAt',
      ],
      'text_box': [
        'id',
        'pageId',
        'type',
        'frame',
        'text',
        'style',
        'createdAt',
        'updatedAt',
      ],
      'image': [
        'id',
        'pageId',
        'type',
        'frame',
        'assetId',
        'px',
        'createdAt',
        'updatedAt',
      ],
      'math': [
        'id',
        'pageId',
        'type',
        'frame',
        'latex',
        'style',
        'createdAt',
        'updatedAt',
      ],
      'unknown': ['id', 'pageId', 'type', 'createdAt', 'updatedAt'],
      'handwriting': [
        'id',
        'noteId',
        'pageId',
        'engineId',
        'sourceRev',
        'lines',
        'createdAt',
        'updatedAt',
      ],
    };
    for (final e in required.entries) {
      final entity = kSampleEntities[e.key]!;
      for (final key in e.value) {
        expect(
          () => EntityJson.decode(entity.kind, _without(entity.toJson(), key)),
          throwsFormatException,
          reason: '${e.key}.$key',
        );
      }
    }
    final folder = kSampleEntities['folder']!;
    expect(
      () =>
          EntityJson.decode(EntityKind.folder, {...folder.toJson(), 'name': 5}),
      throwsFormatException,
    );
    expect(
      () => EntityJson.decode(EntityKind.folder, {
        ...folder.toJson(),
        'version': 'bad',
      }),
      throwsFormatException,
    );
    expect(
      () => EntityJson.decode(EntityKind.page, {
        ...kSampleEntities['page_blank']!.toJson(),
        'background': {'type': 'hologram'},
      }),
      throwsFormatException,
    );
  });

  test('backgrounds and covers round-trip', () {
    const backgrounds = <PageBackground>[
      BlankBackground(),
      TemplateBackground(template: PageTemplate(kind: PageTemplateKind.music)),
      PdfBackground(
        assetId: 'abc',
        pdfPageIndex: 0,
        paperColorArgb: PaperColors.gray,
      ),
      ImageBackground(assetId: 'img', fit: ImageFit.cover),
    ];
    for (final b in backgrounds) {
      expect(PageBackground.fromJson(b.toJson()), b);
    }
    expect(backgrounds[2].referencedAssets, {'abc'});
    expect(backgrounds[3].referencedAssets, {'img'});
    expect(backgrounds[0].referencedAssets, isEmpty);
    const covers = <NoteCover>[
      FirstPageCover(),
      ColorCover(0xFF00FF00),
      AssetCover('a1'),
    ];
    for (final c in covers) {
      expect(NoteCover.fromJson(c.toJson()), c);
    }
    expect(
      PageTemplate.defaults(PageTemplateKind.grid),
      const PageTemplate(kind: PageTemplateKind.grid),
    );
    expect(const PageTemplate(kind: PageTemplateKind.lined).toJson(), {
      'kind': 'lined',
      'spacing': null,
      'lineColor': null,
      'lineWidth': null,
      'extras': <String, Object?>{},
    });
  });

  test('schema constants', () {
    expect(kNoteSchemaVersion, 1);
    expect(kDatabaseSchemaVersion, 3); // (v2.17-md) DB v3 — C217M-03
    expect(kStrokePointsFormatVersion, 1);
    final newer = (kSampleEntities['note']! as Note).copyWith(schemaVersion: 2);
    expect(newer.requiresNewerApp, isTrue);
  });
}
