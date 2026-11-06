// T16-v2 (integration stage 3 — 07-sync 6.7.2, 6.2.9): recordings between two real CORE
// stores. What only real CORE shows: Recording.title in its JSON with a field version of its
// own (title and deletedAt are separate units).
//
// R1 (S29) A renames recording R while B, offline, deletes it: deleted on both AND titled;
// then A and B, both offline, each rename R: the later title wins. R2 A's createRecording
// (its audio asset first, the 1st-round asset path — the fake server's blob store) shows in
// B's watchRecordings with the same asset and title.
//
// CORE milestones (6.7.2 table): R1 · R2 T30 · T28.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import 'support/core_sync_device.dart';

void main() {
  coreScenario('R1 rename vs delete, then two offline renames: separate units; '
      'the later title wins', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final note = (await a.store.library.createNote(title: 'R1')).id;
    final r = (await a.core.createRecording(note)).id;
    final ref = EntityRef(EntityKind.recording, r);
    await s.converge([a, b], [note]);
    expect((await b.jsonOf(ref.kind, ref.id))!['title'], isNull);

    b.goOffline();
    await a.store.recordings.renameRecording(r, '1강');
    await s.settle([a]);
    await nextMillisecond();
    await b.store.recordings.deleteRecording(r);
    b.goOnline();
    await s.converge([a, b], [note], extra: [ref]);
    for (final d in [a, b]) {
      final json = (await d.jsonOf(ref.kind, ref.id))!;
      expect(json['title'], '1강', reason: d.name);
      expect(json['deletedAt'], isNotNull, reason: d.name);
      expect(await d.store.recordings.recordingsOf(note), isEmpty);
    }

    a.goOffline();
    b.goOffline();
    await a.store.recordings.renameRecording(r, '미적분 1강');
    await nextMillisecond();
    await b.store.recordings.renameRecording(r, '미적분 첫 강의'); // later
    b.goOnline();
    await s.settle([b]);
    a.goOnline();
    await s.converge([a, b], [note], extra: [ref]);
    for (final d in [a, b]) {
      final json = (await d.jsonOf(ref.kind, ref.id))!;
      expect(json['title'], '미적분 첫 강의', reason: d.name);
      expect(json['deletedAt'], isNotNull, reason: d.name);
    }
  });

  coreScenario('R2 A\'s new recording shows in B\'s watchRecordings with its '
      'asset', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final note = (await a.store.library.createNote(title: 'R2')).id;
    await s.converge([a, b], [note]);
    final lists = <List<Recording>>[];
    final watch = b.store.recordings.watchRecordings(note).listen(lists.add);

    final recording = await a.core.createRecording(
      note,
      durationMs: 2500,
      title: '첫 녹음',
    );
    await s.until(
      'the recording in B\'s watchRecordings',
      () => lists.isNotEmpty && lists.last.any((r) => r.id == recording.id),
    );
    await s.converge(
      [a, b],
      [note],
      extra: [EntityRef(EntityKind.asset, recording.assetId)],
    );
    final onB = lists.last.singleWhere((r) => r.id == recording.id);
    expect(onB.title, '첫 녹음');
    expect(onB.assetId, recording.assetId);
    expect(onB.durationMs, 2500);
    final blobs = s.server.blobsOf(kT16Uid);
    await s.until(
      'the audio bytes on the server',
      () => blobs.objects.containsKey(blobs.pathFor(recording.assetId)),
    );
    expect(await b.read(EntityKind.asset, recording.assetId), isNotNull);
    unawaited(watch.cancel());
  });
}
