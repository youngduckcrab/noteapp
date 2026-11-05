// Internal (not exported). Field versions ARE CORE EntityFieldVersions (contract 7.2.10);
// SYNC only adds arithmetic.
import 'package:note_core/note_core.dart';

extension EntityFieldVersionsMerge on EntityFieldVersions {
  /// Max over a set of fields (one merge unit, 6.3.1).
  Hlc ofUnit(Iterable<String> fields) => throw UnimplementedError('SYNC T2');

  /// Local-write rule of CORE 6.10.2 (used by FakeLocalStore): '*' → EntityFieldVersions(v),
  /// otherwise each listed field := v, base kept.
  EntityFieldVersions stamped(Iterable<String> fields, Hlc v) =>
      throw UnimplementedError('SYNC T2');
}

/// Normal form of per-field versions: base = min, overrides = fields whose version > base —
/// the same form EntityFieldVersions.fromJson produces ("overrides only > base").
EntityFieldVersions normalizedFieldVersions(Map<String, Hlc> fieldVersions) =>
    throw UnimplementedError('SYNC T2');
