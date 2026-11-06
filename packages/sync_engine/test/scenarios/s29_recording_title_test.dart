// S29 (07-sync 6.7.1, 6.2.9): recording titles. A renames recording R to '1강' while B,
// offline, deletes R: both end deleted AND titled '1강' (title and deletedAt are separate
// units). Then A and B, both offline, each rename R: the later title wins everywhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import 'support/sync_scenario.dart';

void main() {
  syncScenario('S29 rename vs delete, then two renames: separate units; the '
      'later title wins', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S29');
    final r = h.run(a.addRecording(note));
    h.settle();
    expect(b.doc(EntityKind.recording, r)!.json['title'], isNull);

    b.goOffline();
    a.renameRecording(r, '  1강 ');
    h.settle();
    b.deleteRecording(r);
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();
    for (final d in [a, b]) {
      final json = d.doc(EntityKind.recording, r)!.json;
      expect(json['title'], '1강', reason: d.name);
      expect(json['deletedAt'], isNotNull, reason: d.name);
    }
    h.checkConverged([a, b]);

    a.goOffline();
    b.goOffline();
    a.renameRecording(r, '미적분 1강');
    h.elapse(const Duration(seconds: 1));
    b.renameRecording(r, '미적분 첫 강의');
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();
    a.goOnline();
    h.settle();
    for (final d in [a, b]) {
      final json = d.doc(EntityKind.recording, r)!.json;
      expect(json['title'], '미적분 첫 강의', reason: d.name);
      expect(json['deletedAt'], isNotNull, reason: d.name);
    }
    h.checkConverged([a, b]);
  });
}
