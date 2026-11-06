// S26 (07-sync 6.7.1, 6.2.8, C-12): X — standing in for a newer app — writes an object of
// type "sticker" (nested map, list, keys this app does not know) and uploads it. A receives
// it and deletes it; B receives both. On A, B and the server's merged state the object keeps
// the original key set and every original value; only deletedAt (and the store's
// updatedAt / version) change.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import 'support/sync_scenario.dart';

/// Keys the store stamps on every write (C-11) — their values move with the delete.
const Set<String> _stamped = {'deletedAt', 'updatedAt', 'version'};

void main() {
  syncScenario('S26 unknown object type: keys and values survive receive, '
      'delete and a second receive', (h) {
    final x = h.device('X');
    final a = h.device('A');
    final b = h.device('B');
    final note = x.createNote('S26');
    final page = x.pageIdsOf(note).single;
    h.settle();
    const id = 'sticker-1';
    x.putRawObject(page, {
      'id': id,
      'type': 'sticker',
      'frame': [400.0, 100.0, 450.0, 150.0, 0.0],
      'stickerId': 'cat-01',
      'tint': {
        'argb': 4294940672,
        'stops': [0.0, 0.5, 1.0],
      },
      'animation': {
        'loop': true,
        'frames': [
          {'at': 0, 'scale': 1.5},
          {'at': 250, 'scale': 1.25},
        ],
      },
    });
    h.settle();
    final original = x.doc(EntityKind.pageObject, id)!.json;
    expect(original.keys, containsAll(['stickerId', 'tint', 'animation']));
    expect(
      a.store.rows[const EntityRef(EntityKind.pageObject, id)]!.entity,
      isA<UnknownObject>(),
    );
    expect(a.doc(EntityKind.pageObject, id)!.json, original);

    a.deleteObject(id);
    h.settle();

    final server = h.server.mergedState(
      'user-1',
    )[const EntityRef(EntityKind.pageObject, id)]!;
    final sides = {
      'A': a.doc(EntityKind.pageObject, id)!.json,
      'B': b.doc(EntityKind.pageObject, id)!.json,
      'X': x.doc(EntityKind.pageObject, id)!.json,
      'server': server.doc.json,
    };
    for (final MapEntry(key: name, value: json) in sides.entries) {
      expect(json.keys.toSet(), original.keys.toSet(), reason: name);
      expect(json['deletedAt'], isNotNull, reason: name);
      for (final key in original.keys) {
        if (_stamped.contains(key)) continue;
        expect(json[key], original[key], reason: '$name: $key');
      }
    }
    for (final d in [a, b, x]) {
      expect(d.activeObjectsOf(page), isEmpty, reason: d.name);
    }
    h.checkConverged([a, b, x]);
  });
}
