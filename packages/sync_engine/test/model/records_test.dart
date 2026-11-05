import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

void main() {
  final v0 = Hlc.parse(hlcText(kT0));
  final v1 = Hlc.parse(hlcText(kT0 + 60000, counter: 1));

  test('fromVersioned keeps the entity JSON and the CORE field versions', () {
    final entity = fixtureEntity(EntityKind.stroke);
    final versions = EntityFieldVersions(v0, {'style': v1});
    final r = UpsertRecord.fromVersioned(VersionedEntity(entity, versions));
    expect(r.doc, SyncDoc.fromEntity(entity));
    expect(r.versions, versions);
    expect(r.ref, const EntityRef(EntityKind.stroke, 's1'));
  });

  test('toRemoteChange decodes the entity with the same versions', () {
    for (final kind in EntityKind.values) {
      final entity = fixtureEntity(kind);
      final r = UpsertRecord(
        SyncDoc.fromEntity(entity),
        EntityFieldVersions(v0),
      );
      final change = r.toRemoteChange();
      expect(change.entity, entity, reason: kind.name);
      expect(change.versions, EntityFieldVersions(v0));
      expect(change.kind, kind);
      expect(change.id, entity.id);
    }
  });

  test('decode errors surface as FormatException', () {
    final json = fixtureJson(EntityKind.folder)..['name'] = 7;
    final r = UpsertRecord(
      SyncDoc(kind: EntityKind.folder, id: 'f1', json: json),
      EntityFieldVersions(v0),
    );
    expect(r.toRemoteChange, throwsFormatException);
  });

  test('PurgeRecord maps to RemotePurge', () {
    final p = PurgeRecord(const EntityRef(EntityKind.note, 'n9'), v1);
    final change = p.toRemoteChange();
    expect(change.kind, EntityKind.note);
    expect(change.id, 'n9');
    expect(p.ref, const EntityRef(EntityKind.note, 'n9'));
  });

  test('value equality', () {
    final e = fixtureEntity(EntityKind.page);
    UpsertRecord u() =>
        UpsertRecord(SyncDoc.fromEntity(e), EntityFieldVersions(v0));
    expect(u(), u());
    expect(u().hashCode, u().hashCode);
    expect(
      UpsertRecord(SyncDoc.fromEntity(e), EntityFieldVersions(v1)),
      isNot(u()),
    );
    final p = PurgeRecord(const EntityRef(EntityKind.folder, 'f1'), v0);
    expect(p, PurgeRecord(const EntityRef(EntityKind.folder, 'f1'), v0));
    expect(p, isNot(PurgeRecord(const EntityRef(EntityKind.folder, 'f1'), v1)));
  });
}
