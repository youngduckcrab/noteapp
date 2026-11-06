// CORE T28 — field-level LWW over the DB v2 kinds (m5-7/02-core 6.13, 8.2; SYNC 6.3.4 shape —
// fieldLwwPolicy, one unit per JSON key): two stores edit the same page object, recording and
// handwriting result while offline; B pushes first, A receives, A pushes, B receives. Both end
// with the same entity JSON and field versions and empty outboxes. Local edits go through the
// write queue (tx.putLocal with the changed keys) — the object commands of the real store's
// sessions are CORE T27, the recording / handwriting repositories T30 / T32.
@TestOn('vm')
library;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart' show PageObjectFixtures;
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import 'support/sync_support.dart';

const String _nodeA = '000000000000000a';
const String _nodeB = '000000000000000b';

final class _Device {
  _Device(this.store, this._setNow);
  final DriftNoteStore store;
  final void Function(Duration) _setNow;

  /// Sets this device's wall clock to the scenario start + [d].
  void at(Duration d) => _setNow(d);

  /// A local edit of [e] whose JSON keys [fields] changed.
  Future<void> edit(SyncEntity e, Set<String> fields) =>
      store.queue.run((tx) => tx.putLocal(e, fields));

  Future<VersionedEntity> read(EntityKind kind, String id) async =>
      (await store.sync.readVersioned([EntityRef(kind, id)])).single!;

  Future<int> pendingCount() async =>
      (await store.sync.pendingChanges()).length;
}

Future<_Device> _open(String node, DateTime base) async {
  var now = base;
  final store = await openTestNoteStore(
    clock: Clock(() => now),
    ids: SequentialIdGenerator(prefix: node),
    deviceNodeId: node,
    seedDefaultPenPresets: false,
  );
  return _Device(store as DriftNoteStore, (d) => now = base.add(d));
}

const Duration _t1 = Duration(minutes: 1);
const Duration _t2 = Duration(minutes: 2);
const Duration _t3 = Duration(minutes: 3);

/// The shared start: A's note (first page), a text box, a recording and a handwriting result,
/// pushed to B; then [offline] edits on each side, B → A, A → B. Returns both sides' records
/// of [ref] (JSON and versions) and the pending counts.
Future<({VersionedEntity a, VersionedEntity b, int aPending, int bPending})>
_scenario(
  EntityRef Function(_Start s) ref,
  Future<void> Function(_Device a, _Device b, _Start s) offline,
) async {
  final base = DateTime.utc(2026, 11, 6, 9);
  final a = await _open(_nodeA, base);
  final b = await _open(_nodeB, base);
  try {
    final policy = fieldLwwPolicy();
    final note = await a.store.library.createNote(title: 'n');
    final pageId = (await a.store.library.getNote(note.id))!.firstPageId!;
    final t0 = base.millisecondsSinceEpoch;
    final text = PageObjectFixtures.textBox(
      pageId: pageId,
      id: 'obj-1',
      text: 'start',
      createdAt: t0,
    );
    final recording = Recording(
      id: 'rec-1',
      noteId: note.id,
      assetId: 'a' * 64,
      durationMs: 1000,
      startedAt: t0,
      createdAt: t0,
      updatedAt: t0,
    );
    final hw = HandwritingText(
      noteId: note.id,
      pageId: pageId,
      engineId: 'fake/1:ko',
      sourceRev: '0000000000000000',
      lines: const [],
      createdAt: t0,
    );
    for (final e in [text, recording, hw]) {
      await a.edit(e, const {kAllFields});
    }
    await push(a.store, b.store, policy);
    final s = _Start(note.id, pageId, text, recording, hw, t0);

    await offline(a, b, s);
    a.at(_t3);
    b.at(_t3);
    await push(b.store, a.store, policy);
    await push(a.store, b.store, policy);
    final r = ref(s);
    return (
      a: await a.read(r.kind, r.id),
      b: await b.read(r.kind, r.id),
      aPending: await a.pendingCount(),
      bPending: await b.pendingCount(),
    );
  } finally {
    await a.store.close();
    await b.store.close();
  }
}

final class _Start {
  _Start(this.noteId, this.pageId, this.text, this.recording, this.hw, this.t0);
  final NoteId noteId;
  final PageId pageId;
  final TextBoxObject text;
  final Recording recording;
  final HandwritingText hw;
  final int t0;
  int ms(Duration d) => t0 + d.inMilliseconds;
}

void _expectConverged(
  ({VersionedEntity a, VersionedEntity b, int aPending, int bPending}) o,
) {
  expect(o.a.entity.toJson(), o.b.entity.toJson());
  expect(o.a.versions, o.b.versions);
  expect(o.a.entity.version, o.a.versions.max);
  expect((o.aPending, o.bPending), (0, 0));
}

void main() {
  // Two devices = two databases open at once on purpose.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  EntityRef objectRef(_Start s) => EntityRef(EntityKind.pageObject, s.text.id);

  test(
    'an object edited on both sides: each key keeps its newer value',
    () async {
      final o = await _scenario(objectRef, (a, b, s) async {
        a.at(_t1);
        await a.edit(
          s.text.copyWith(text: 'from A', updatedAt: s.ms(_t1)),
          const {'text', 'updatedAt'},
        );
        b.at(_t2);
        final moved = s.text
            .transformed(Affine2.translation(40, 0))
            .copyWithMeta(updatedAt: s.ms(_t2));
        await b.edit(moved, const {'frame', 'updatedAt'});
      });
      _expectConverged(o);
      final t = o.a.entity as TextBoxObject;
      expect(t.text, 'from A');
      expect(t.frame.rect.left, _textLeft + 40);
    },
  );

  test('the same key on both sides: the later edit wins', () async {
    final o = await _scenario(objectRef, (a, b, s) async {
      a.at(_t1);
      await a.edit(s.text.copyWith(text: 'A', updatedAt: s.ms(_t1)), const {
        'text',
      });
      b.at(_t2);
      await b.edit(s.text.copyWith(text: 'B', updatedAt: s.ms(_t2)), const {
        'text',
      });
    });
    _expectConverged(o);
    expect((o.a.entity as TextBoxObject).text, 'B');
  });

  test(
    'delete against modify: both sides end deleted with the new text',
    () async {
      final o = await _scenario(objectRef, (a, b, s) async {
        a.at(_t1);
        await a.edit(s.text.copyWithMeta(deletedAt: s.ms(_t1)), const {
          'deletedAt',
        });
        b.at(_t2);
        await b.edit(
          s.text.copyWith(text: 'edited', updatedAt: s.ms(_t2)),
          const {'text'},
        );
      });
      _expectConverged(o);
      final t = o.a.entity as TextBoxObject;
      expect(t.isDeleted, isTrue);
      expect(t.text, 'edited');
    },
  );

  test('a recording title against a delete', () async {
    final o = await _scenario(
      (s) => EntityRef(EntityKind.recording, s.recording.id),
      (a, b, s) async {
        a.at(_t1);
        await a.edit(
          s.recording.copyWith(title: '1교시', updatedAt: s.ms(_t1)),
          const {'title'},
        );
        b.at(_t2);
        await b.edit(
          s.recording.copyWith(deletedAt: s.ms(_t2), updatedAt: s.ms(_t2)),
          const {'deletedAt'},
        );
      },
    );
    _expectConverged(o);
    final r = o.a.entity as Recording;
    expect((r.title, r.isDeleted), ('1교시', true));
  });

  test(
    'handwriting results: the later lines win, the other keys merge',
    () async {
      const lineA = HandwritingLine(
        text: 'A',
        rect: PageRect(0, 0, 10, 10),
        strokeIds: ['s1'],
      );
      const lineB = HandwritingLine(
        text: 'B',
        rect: PageRect(0, 0, 10, 10),
        strokeIds: ['s1'],
        userConfirmed: true,
      );
      final o = await _scenario(
        (s) => EntityRef(EntityKind.handwriting, s.hw.id),
        (a, b, s) async {
          a.at(_t1);
          await a.edit(
            s.hw.copyWith(lines: const [lineA], engineId: 'fake/2:ko'),
            const {'lines', 'engineId'},
          );
          b.at(_t2);
          await b.edit(
            s.hw.copyWith(lines: const [lineB], sourceRev: '1111111111111111'),
            const {'lines', 'sourceRev'},
          );
        },
      );
      _expectConverged(o);
      final h = o.a.entity as HandwritingText;
      expect(h.lines, const [lineB]);
      expect(h.engineId, 'fake/2:ko');
      expect(h.sourceRev, '1111111111111111');
    },
  );
}

/// The left edge of PageObjectFixtures.textBox's default rect.
const double _textLeft = 100;
