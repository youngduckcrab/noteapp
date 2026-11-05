import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

void main() {
  group('immutability and id check', () {
    test('json is deep-copied and unmodifiable', () {
      final source = fixtureJson(EntityKind.note);
      final doc = SyncDoc(kind: EntityKind.note, id: 'n1', json: source);
      (source['tags']! as List<Object?>).add('changed');
      source['title'] = 'changed';
      expect(doc.json['title'], '강의노트');
      expect(doc.json['tags'], ['math', '2학기']);
      expect(() => doc.json['title'] = 'x', throwsUnsupportedError);
      expect(
        () => (doc.json['tags']! as List<Object?>).add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => (doc.json['cover']! as Map<String, Object?>)['color'] = 1,
        throwsUnsupportedError,
      );
    });

    test('json id (setting: key) must equal id', () {
      expect(
        () => SyncDoc(
          kind: EntityKind.note,
          id: 'other',
          json: fixtureJson(EntityKind.note),
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncDoc(kind: EntityKind.note, id: 'n1', json: const {}),
        throwsArgumentError,
      );
      final setting = SyncDoc(
        kind: EntityKind.setting,
        id: 'editor.theme',
        json: fixtureJson(EntityKind.setting),
      );
      expect(setting.ref, const EntityRef(EntityKind.setting, 'editor.theme'));
      expect(
        () => SyncDoc(
          kind: EntityKind.setting,
          id: 'editor.theme',
          json: {...fixtureJson(EntityKind.setting), 'key': 'x'},
        ),
        throwsArgumentError,
      );
    });

    test('value equality', () {
      SyncDoc make() => SyncDoc(
        kind: EntityKind.page,
        id: 'p1',
        json: fixtureJson(EntityKind.page),
      );
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      expect(make().withFields({'sortKey': 'b0'}), isNot(make()));
    });
  });

  group('CORE entities', () {
    for (final kind in EntityKind.values) {
      test('${kind.name}: fromEntity → toEntity round trip', () {
        final entity = fixtureEntity(kind);
        final doc = SyncDoc.fromEntity(entity);
        expect(doc.kind, kind);
        expect(doc.id, entity.id);
        expect(doc.json, entity.toJson());
        expect(doc.json, fixtureJson(kind));
        final back = doc.toEntity();
        expect(back, entity);
        expect(back.toJson(), entity.toJson());
      });
    }

    test('integer-valued doubles (web jsonEncode form) decode', () {
      final page = fixtureJson(EntityKind.page)..['size'] = [540, 960];
      final pageEntity = SyncDoc(
        kind: EntityKind.page,
        id: 'p1',
        json: page,
      ).toEntity();
      expect(pageEntity.toJson()['size'], [540.0, 960.0]);

      final stroke = fixtureJson(EntityKind.stroke);
      stroke['style'] = {
        ...(stroke['style']! as Map<String, Object?>),
        'width': 2,
        'opacity': 1,
        'pressureCurve': [0, 0, 1, 1],
      };
      final strokeJson = SyncDoc(
        kind: EntityKind.stroke,
        id: 's1',
        json: stroke,
      ).toEntity().toJson();
      final style = strokeJson['style']! as Map<String, Object?>;
      expect(style['width'], 2.0);
      expect(style['opacity'], 1.0);
      expect(style['pressureCurve'], [0.0, 0.0, 1.0, 1.0]);
    });
  });

  group('accessors', () {
    test('ownerId only for folder / note / penPreset / asset', () {
      for (final kind in EntityKind.values) {
        final doc = SyncDoc.fromEntity(fixtureEntity(kind));
        final hasOwner = {
          EntityKind.folder,
          EntityKind.note,
          EntityKind.penPreset,
          EntityKind.asset,
        }.contains(kind);
        expect(doc.ownerId, hasOwner ? 'local' : isNull, reason: kind.name);
      }
    });

    test('isDeleted and version', () {
      final doc = SyncDoc.fromEntity(fixtureEntity(EntityKind.stroke));
      expect(doc.isDeleted, isFalse);
      expect(doc.withFields({'deletedAt': kT0}).isDeleted, isTrue);
      expect(doc.version, Hlc.parse(hlcText(kT0)));
      expect(doc.withFields({'version': null}).version, isNull);
      expect(
        () => doc.withFields({'version': 'not-an-hlc'}).version,
        throwsFormatException,
      );
      expect(
        () => doc.withFields({'version': 5}).version,
        throwsFormatException,
      );
    });

    test('withFields is a shallow merge of top-level keys', () {
      final doc = SyncDoc.fromEntity(fixtureEntity(EntityKind.folder));
      final moved = doc.withFields({'parentId': 'f0', 'sortKey': 'b1'});
      expect(moved.json['parentId'], 'f0');
      expect(moved.json['sortKey'], 'b1');
      expect(moved.json['name'], doc.json['name']);
      expect(doc.json['parentId'], isNull);
    });
  });

  group('toEntity errors are FormatException', () {
    test('missing required key', () {
      final json = fixtureJson(EntityKind.note)..remove('title');
      expect(
        () => SyncDoc(kind: EntityKind.note, id: 'n1', json: json).toEntity(),
        throwsFormatException,
      );
    });

    test('wrong value type', () {
      final json = fixtureJson(EntityKind.stroke)..['points'] = 42;
      expect(
        () => SyncDoc(kind: EntityKind.stroke, id: 's1', json: json).toEntity(),
        throwsFormatException,
      );
      final json2 = fixtureJson(EntityKind.page)..['size'] = 'big';
      expect(
        () => SyncDoc(kind: EntityKind.page, id: 'p1', json: json2).toEntity(),
        throwsFormatException,
      );
    });
  });
}
