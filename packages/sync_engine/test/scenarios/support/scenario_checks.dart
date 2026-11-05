// test/ only. Checks shared by the scenarios (9.1.1): no-loss, entity lookups, waiting for
// a condition in virtual time. They throw TestFailure through expect (flutter_test).
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/testing.dart';

/// The entity [kind]/[id] on [d], or null.
T? entityOn<T extends SyncEntity>(TestDevice d, EntityKind kind, String id) =>
    d.store.rows[EntityRef(kind, id)]?.entity as T?;

Note noteOn(TestDevice d, String id) => entityOn<Note>(d, EntityKind.note, id)!;

Stroke? strokeOn(TestDevice d, String id) =>
    entityOn<Stroke>(d, EntityKind.stroke, id);

/// Every stroke row of [d] (soft-deleted included).
Set<String> strokeIdsOn(TestDevice d) => {
  for (final ref in d.store.rows.keys)
    if (ref.kind == EntityKind.stroke) ref.id,
};

/// 9.1.1 no loss: every stroke in [created] exists on every device, and the ones not in
/// [erased] are active everywhere.
void expectNoLoss(
  Iterable<TestDevice> devices,
  Iterable<String> created, {
  Set<String> erased = const {},
}) {
  for (final d in devices) {
    final ids = strokeIdsOn(d);
    final missing = [
      for (final id in created)
        if (!ids.contains(id)) id,
    ];
    expect(missing, isEmpty, reason: '${d.name}: strokes lost');
    final inactive = [
      for (final id in created)
        if (!erased.contains(id) && strokeOn(d, id)!.isDeleted) id,
    ];
    expect(inactive, isEmpty, reason: '${d.name}: strokes deleted');
  }
}

/// Elapses in [step]s until [done] holds; returns the virtual time it took. Fails after
/// [max].
Duration elapseUntil(
  SyncTestHarness h,
  bool Function() done, {
  Duration max = const Duration(minutes: 1),
  Duration step = const Duration(milliseconds: 10),
}) {
  var waited = Duration.zero;
  while (!done()) {
    if (waited >= max) fail('condition not reached after $max');
    h.elapse(step);
    waited += step;
  }
  return waited;
}
