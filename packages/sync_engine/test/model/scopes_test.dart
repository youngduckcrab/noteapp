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

  // --- (2nd round, S2-2, contract 7.2.8, 07-sync 6.2.3) ---------------------------
  test('pageObject goes to the outbox noteId hint like a stroke (no noteId in '
      'its JSON)', () {
    final object = rec(EntityKind.pageObject);
    expect(object.doc.json.containsKey('noteId'), isFalse);
    expect(SyncScopes.scopeOf(object, noteIdHint: 'n7'), 'n7');
    expect(SyncScopes.scopeOf(object), SyncScopes.library);
    for (final type in ['text', 'image', 'math', 'sticker']) {
      final o = objectFixture(type);
      final r = UpsertRecord(
        SyncDoc.fromEntity(o),
        EntityFieldVersions(o.version!),
      );
      expect(SyncScopes.scopeOf(r, noteIdHint: 'n7'), 'n7', reason: type);
    }
  });

  UpsertRecord withNoteId(EntityKind kind, Object? noteId) {
    final r = rec(kind);
    final json = {...r.doc.json};
    if (noteId == #absent) {
      json.remove('noteId');
    } else {
      json['noteId'] = noteId;
    }
    return UpsertRecord(
      SyncDoc(kind: kind, id: r.doc.id, json: json),
      r.versions,
    );
  }

  test('handwriting uses the same order as page: json noteId, then the hint, '
      'then lib', () {
    for (final kind in [EntityKind.page, EntityKind.handwriting]) {
      // JSON noteId wins over the hint.
      expect(
        SyncScopes.scopeOf(withNoteId(kind, 'n1'), noteIdHint: 'n7'),
        'n1',
        reason: kind.name,
      );
      expect(SyncScopes.scopeOf(withNoteId(kind, 'n1')), 'n1');
      // Empty or missing JSON noteId: the hint, then lib.
      for (final missing in <Object?>['', null, #absent]) {
        expect(
          SyncScopes.scopeOf(withNoteId(kind, missing), noteIdHint: 'n7'),
          'n7',
          reason: '${kind.name} $missing',
        );
        expect(
          SyncScopes.scopeOf(withNoteId(kind, missing)),
          SyncScopes.library,
          reason: '${kind.name} $missing',
        );
      }
    }
    // recording keeps its v1.4 order (hint first) — different from page.
    expect(
      SyncScopes.scopeOf(
        withNoteId(EntityKind.recording, 'n1'),
        noteIdHint: 'n7',
      ),
      'n7',
    );
  });

  test('purges always go to lib', () {
    final p = PurgeRecord(
      const EntityRef(EntityKind.note, 'n1'),
      Hlc.parse(hlcText(kT0)),
    );
    expect(SyncScopes.scopeOfPurge(p), 'lib');
  });
}
