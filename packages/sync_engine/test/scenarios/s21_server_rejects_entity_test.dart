// S21 (9.1.2, 6.5.6): the server rejects one stroke record (invalidArgument). Only that
// entry is quarantined (rejectedByServer, display error); everything else converges.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/sync_engine.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S21 one rejected stroke is quarantined, the rest converges', (
    h,
  ) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S21');
    h.settle();
    final page = a.pageIdsOf(note).single;
    final good1 = a.addStroke(page, seed: 1);
    final bad = a.addStroke(page, seed: 2);
    final good2 = a.addStroke(page, seed: 3);
    a.link.rejectCommitsWhere(
      (chunk) => ChunkCodec.decode(chunk.payload).any((r) => r.ref.id == bad),
      SyncErrorCode.invalidArgument,
    );
    h.settle();
    final status = a.engine.status;
    expect(status.quarantinedUploads, 1);
    expect(status.display, SyncDisplayState.error);
    final issue = status.issues.singleWhere(
      (i) => i.code == SyncIssueCode.rejectedByServer,
    );
    expect(issue.ref, EntityRef(EntityKind.stroke, bad));
    expect(a.engine.debug.quarantined, {EntityRef(EntityKind.stroke, bad)});
    expect(strokeOn(b, bad), isNull);
    expectNoLoss([a, b], [good1, good2]);
    expect(
      b.store.canonicalDump(),
      {...a.store.canonicalDump()}..remove('stroke/$bad'),
    );
  });
}
