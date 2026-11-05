// Internal: sortKey placement with the equal-key recovery of CORE 6.6. Shared by the
// session (InsertPages, MovePages, DuplicatePages) and the repositories (reorderItems, ...).
import 'sort_keys.dart';

typedef KeyedId = ({String key, String id});

/// Keys for [count] new items placed at [index] of [siblings] (sorted by (key, id), the
/// items being placed already removed).
///
/// [keys] are ascending and strictly between the neighbours. When the two neighbours share
/// a key (only after sync merges) the run of equal keys after the insertion point is
/// re-keyed together with the new items; [rekeyed] holds those siblings' new keys (6.6).
({List<String> keys, Map<String, String> rekeyed}) planSortKeys(
  List<KeyedId> siblings,
  int index,
  int count,
) {
  RangeError.checkValueInInterval(index, 0, siblings.length, 'index');
  final prev = index > 0 ? siblings[index - 1].key : null;
  final next = index < siblings.length ? siblings[index].key : null;
  if (prev == null || next == null || prev.compareTo(next) < 0) {
    return (keys: SortKeys.nBetween(prev, next, count), rekeyed: const {});
  }
  // prev == next: re-key the equal run after the insertion point.
  var end = index;
  while (end < siblings.length && siblings[end].key == prev) {
    end++;
  }
  final nextDifferent = end < siblings.length ? siblings[end].key : null;
  final all = SortKeys.nBetween(prev, nextDifferent, count + (end - index));
  return (
    keys: all.sublist(0, count),
    rekeyed: {
      for (var i = index; i < end; i++) siblings[i].id: all[count + i - index],
    },
  );
}

/// Key after every sibling (new folder / note / preset default position, 6.6).
String sortKeyAfterAll(Iterable<String> siblingKeys) {
  String? max;
  for (final k in siblingKeys) {
    if (max == null || k.compareTo(max) > 0) max = k;
  }
  return SortKeys.between(max, null);
}
