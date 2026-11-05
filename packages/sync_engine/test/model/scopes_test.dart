import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

UpsertRecord rec(EntityKind kind) {
  final e = fixtureEntity(kind);
  return UpsertRecord(SyncDoc.fromEntity(e), EntityFieldVersions(e.version!));
}

void main() {
  test('library-level kinds go to lib', () {
    for (final k in [
      EntityKind.folder,
      EntityKind.note,
      EntityKind.penPreset,
      EntityKind.setting,
      EntityKind.asset,
    ]) {
      expect(
        SyncScopes.scopeOf(rec(k), noteIdHint: 'nX'),
        SyncScopes.library,
        reason: k.name,
      );
    }
  });

  test("page goes to its json['noteId']", () {
    expect(SyncScopes.scopeOf(rec(EntityKind.page)), 'n1');
  });

  test('stroke and recording go to the outbox noteId hint', () {
    expect(SyncScopes.scopeOf(rec(EntityKind.stroke), noteIdHint: 'n7'), 'n7');
    expect(
      SyncScopes.scopeOf(rec(EntityKind.recording), noteIdHint: 'n7'),
      'n7',
    );
    expect(SyncScopes.scopeOf(rec(EntityKind.recording)), 'n1');
    expect(SyncScopes.scopeOf(rec(EntityKind.stroke)), SyncScopes.library);
  });

  test('purges always go to lib', () {
    final p = PurgeRecord(
      const EntityRef(EntityKind.note, 'n1'),
      Hlc.parse(hlcText(kT0)),
    );
    expect(SyncScopes.scopeOfPurge(p), 'lib');
  });
}
