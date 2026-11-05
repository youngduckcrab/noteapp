// Internal (not exported). Bounded set that forgets the least recently added or touched
// element — the applied-chunk memory of the download pipeline (6.6.2).
import 'dart:collection';

final class LruSet<T> {
  LruSet(this.capacity) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be >= 1');
    }
  }

  final int capacity;
  final LinkedHashSet<T> _items = LinkedHashSet<T>();

  int get length => _items.length;

  /// Does not change the recency order.
  bool contains(T value) => _items.contains(value);

  /// Adds [value] (or marks it most recent). Returns true when it was not present.
  /// Evicts the least recent element when over [capacity].
  bool add(T value) {
    final isNew = !_items.remove(value);
    _items.add(value);
    if (_items.length > capacity) _items.remove(_items.first);
    return isNew;
  }

  bool remove(T value) => _items.remove(value);

  void clear() => _items.clear();

  /// Least recent first.
  List<T> toList() => _items.toList(growable: false);
}
