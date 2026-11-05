import 'package:note_core/note_core.dart';

/// Merge units (6.3.1). Keys not listed in a group form their own unit.
abstract final class FieldUnits {
  /// Never merged by LWW: identity and derived values (CORE never puts them in
  /// changedFields — CORE 6.3).
  static const Set<String> metaKeys = {
    'id',
    'key',
    'version',
    'createdAt',
    'updatedAt',
  };

  /// Explicit multi-key groups per kind (table 6.3.1).
  static List<Set<String>> groupsOf(EntityKind kind) =>
      throw UnimplementedError('SYNC T2');

  /// All units for the keys present in either snapshot (metaKeys excluded).
  static List<Set<String>> unitsFor(EntityKind kind, Iterable<String> keys) =>
      throw UnimplementedError('SYNC T2');
}
