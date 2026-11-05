// Internal (not exported). Field versions ARE CORE EntityFieldVersions (contract 7.2.10);
// SYNC only adds arithmetic.
import 'package:note_core/note_core.dart';

extension EntityFieldVersionsMerge on EntityFieldVersions {
  /// Max over a set of fields (one merge unit, 6.3.1).
  Hlc ofUnit(Iterable<String> fields) {
    var m = base;
    for (final f in fields) {
      final v = of(f);
      if (v > m) m = v;
    }
    return m;
  }

  /// Local-write rule of CORE 6.10.2 (used by FakeLocalStore): '*' → EntityFieldVersions(v),
  /// otherwise each listed field := v, base kept.
  EntityFieldVersions stamped(Iterable<String> fields, Hlc v) {
    final list = fields.toList();
    if (list.contains(kAllFields)) return EntityFieldVersions(v);
    final next = <String, Hlc>{...overrides, for (final f in list) f: v};
    return _normalForm(base, next);
  }
}

/// Normal form of per-field versions: base = min, overrides = fields whose version > base —
/// the same form EntityFieldVersions.fromJson produces ("overrides only > base").
EntityFieldVersions normalizedFieldVersions(Map<String, Hlc> fieldVersions) {
  if (fieldVersions.isEmpty) {
    throw ArgumentError.value(fieldVersions, 'fieldVersions', 'is empty');
  }
  var base = fieldVersions.values.first;
  for (final v in fieldVersions.values) {
    if (v < base) base = v;
  }
  return _normalForm(base, fieldVersions);
}

EntityFieldVersions _normalForm(Hlc base, Map<String, Hlc> fields) {
  final keys = fields.keys.toList()..sort();
  return EntityFieldVersions(
    base,
    Map<String, Hlc>.unmodifiable({
      for (final k in keys)
        if (fields[k]! > base) k: fields[k]!,
    }),
  );
}
