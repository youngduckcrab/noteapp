import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/merge_recorder.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

Hlc h(int t, [String node = kNodeA]) => Hlc(kT0 + t, 0, node);

VersionedEntity noteV(
  String id, {
  Map<String, Object?> set = const {},
  Map<String, Hlc> fv = const {},
}) {
  final versions = EntityFieldVersions(h(0), fv);
  final json = {
    ...fixtureJson(EntityKind.note, id: id),
    ...set,
    'version': versions.max.toString(),
  };
  return VersionedEntity(EntityJson.decode(EntityKind.note, json), versions);
}

EntityRef ref(String id) => EntityRef(EntityKind.note, id);

void main() {
  late MergeRecorder recorder;
  late RemoteMergePolicy policy;

  setUp(() {
    recorder = MergeRecorder();
    policy = recorder.wrap(SyncMergePolicy.decide);
  });

  test('records created / taken / merged / kept per ref', () {
    recorder.beginCall();
    policy(null, noteV('n1'), null); // new → created
    policy(
      noteV('n2'),
      noteV('n2', set: {'title': 'x'}, fv: {'title': h(3, kNodeB)}),
      null,
    ); // taken
    policy(
      noteV('n3', set: {'title': 'mine'}, fv: {'title': h(4)}),
      noteV(
        'n3',
        set: {
          'tags': ['z'],
        },
        fv: {'tags': h(5, kNodeB)},
      ),
      {'title'},
    ); // merged
    policy(noteV('n4'), noteV('n4'), null); // echo → kept
    policy(null, noteV('n5'), {kAllFields}); // unsent purge → kept
    expect(recorder.outcomes, isEmpty, reason: 'not committed yet');
    recorder.commitCall();
    expect(recorder.outcomes, {
      ref('n1'): MergeOutcomeKind.created,
      ref('n2'): MergeOutcomeKind.taken,
      ref('n3'): MergeOutcomeKind.merged,
      ref('n4'): MergeOutcomeKind.kept,
      ref('n5'): MergeOutcomeKind.kept,
    });
  });

  test('the wrapped policy returns the inner decision', () {
    recorder.beginCall();
    expect(policy(null, noteV('n1'), {kAllFields}), isA<KeepLocal>());
    expect(policy(null, noteV('n1'), null), isA<TakeRemote>());
    recorder.discardCall();
  });

  test('a discarded call leaves nothing behind', () {
    recorder.beginCall();
    policy(null, noteV('n1'), null);
    recorder.discardCall();
    expect(recorder.outcomes, isEmpty);
    expect(recorder.isCallOpen, isFalse);

    recorder.beginCall();
    policy(null, noteV('n2'), null);
    recorder.commitCall();
    recorder.beginCall();
    policy(noteV('n2'), noteV('n2'), null);
    recorder.discardCall();
    expect(recorder.outcomes, {ref('n2'): MergeOutcomeKind.created});
  });

  test('two calls combine; an earlier created survives a later outcome', () {
    recorder.beginCall();
    policy(null, noteV('n1'), null);
    recorder.commitCall();
    recorder.beginCall();
    policy(
      noteV('n1'),
      noteV('n1', set: {'title': 'x'}, fv: {'title': h(2, kNodeB)}),
      null,
    );
    policy(null, noteV('n2'), null);
    recorder.commitCall();
    recorder.beginCall();
    policy(noteV('n2'), noteV('n2'), null);
    policy(noteV('n3'), noteV('n3'), null);
    recorder.commitCall();
    recorder.beginCall();
    policy(
      noteV('n3'),
      noteV('n3', set: {'title': 'y'}, fv: {'title': h(2, kNodeB)}),
      null,
    );
    recorder.commitCall();
    expect(recorder.outcomes, {
      ref('n1'): MergeOutcomeKind.created,
      ref('n2'): MergeOutcomeKind.created,
      ref('n3'): MergeOutcomeKind.taken, // later call wins
    });
  });

  test('a CORE retry inside one call overwrites by ref', () {
    recorder.beginCall();
    policy(null, noteV('n1'), null);
    policy(null, noteV('n1'), null);
    recorder.commitCall();
    expect(recorder.outcomes, {ref('n1'): MergeOutcomeKind.created});
  });

  test('clear forgets the group', () {
    recorder.beginCall();
    policy(null, noteV('n1'), null);
    recorder.commitCall();
    recorder.clear();
    expect(recorder.outcomes, isEmpty);
  });

  test('misuse is a StateError', () {
    // Policy with no open call.
    expect(() => policy(null, noteV('n1'), null), throwsStateError);
    expect(recorder.commitCall, throwsStateError);
    expect(recorder.discardCall, throwsStateError);
    recorder.beginCall();
    expect(recorder.beginCall, throwsStateError);
    expect(recorder.clear, throwsStateError);
    recorder.commitCall();
    expect(() => policy(null, noteV('n1'), null), throwsStateError);
  });

  test('outcomes is a read-only view', () {
    expect(
      () => recorder.outcomes[ref('x')] = MergeOutcomeKind.kept,
      throwsUnsupportedError,
    );
  });

  test('the same input twice gives the same outcomes', () {
    Map<EntityRef, MergeOutcomeKind> run() {
      final r = MergeRecorder();
      final p = r.wrap(SyncMergePolicy.decide);
      r.beginCall();
      p(null, noteV('n1'), null);
      p(
        noteV('n3', set: {'title': 'mine'}, fv: {'title': h(4)}),
        noteV(
          'n3',
          set: {
            'tags': ['z'],
          },
          fv: {'tags': h(5, kNodeB)},
        ),
        {'title'},
      );
      r.commitCall();
      return r.outcomes;
    }

    expect(run(), run());
  });
}
