// lib/src/storage/change_bus.dart (internal) — one ChangeBatch per origin per commit
// (CORE 4.8.1, 6.10.3).
import 'dart:async';

import '../common/ids.dart';
import '../repo/events.dart';
import '../session/page_content.dart';
import '../sync/outbox_types.dart';

/// Batches of one commit: consecutive jobs with the same origin share a batch; an
/// entity changed twice keeps its first position and its last value.
List<ChangeBatch> batchesOf(
  List<(ChangeOrigin, List<EntityChange>)> jobs,
  EpochMillis committedAt,
) {
  final out = <ChangeBatch>[];
  ChangeOrigin? origin;
  var current = <EntityRef, EntityChange>{};
  void close() {
    if (origin != null && current.isNotEmpty) {
      out.add(
        ChangeBatch(
          origin: origin,
          changes: List.unmodifiable(current.values),
          committedAt: committedAt,
        ),
      );
    }
  }

  for (final (o, changes) in jobs) {
    if (changes.isEmpty) continue;
    if (o != origin) {
      close();
      origin = o;
      current = {};
    }
    for (final c in changes) {
      current[EntityRef(c.kind, c.id)] = c;
    }
  }
  close();
  return out;
}

final class ChangeBus {
  final StreamController<ChangeBatch> _ctrl = StreamController.broadcast();

  Stream<ChangeBatch> get stream => _ctrl.stream;

  void publish(List<ChangeBatch> batches) {
    if (_ctrl.isClosed) return;
    batches.forEach(_ctrl.add);
  }

  Future<void> close() => _ctrl.close();
}
