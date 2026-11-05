// lib/src/repo/settings_repository.dart — contract 00-overview 7.2.9 / CORE 4.5.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'settings_internal.dart';

enum SettingScope { synced, device }

/// Typed setting key. Each area declares its own keys in its own package with an
/// '<area>.' prefix: 'editor.penOnlyMode', 'library.viewMode', ... ('sync.' is reserved for
/// the SYNC meta KV and rejected with ArgumentError).
@immutable
final class SettingKey<T> {
  const SettingKey(
    this.name, {
    required this.defaultValue,
    required this.encode,
    required this.decode,
    this.scope = SettingScope.synced,
  });

  static SettingKey<bool> boolean(
    String name,
    bool defaultValue, {
    SettingScope scope = SettingScope.synced,
  }) => SettingKey<bool>(
    name,
    defaultValue: defaultValue,
    encode: _identity,
    decode: _decodeBool,
    scope: scope,
  );

  static SettingKey<int> integer(
    String name,
    int defaultValue, {
    SettingScope scope = SettingScope.synced,
  }) => SettingKey<int>(
    name,
    defaultValue: defaultValue,
    encode: _identity,
    decode: _decodeInt,
    scope: scope,
  );

  static SettingKey<double> number(
    String name,
    double defaultValue, {
    SettingScope scope = SettingScope.synced,
  }) => SettingKey<double>(
    name,
    defaultValue: defaultValue,
    encode: _identity,
    decode: _decodeDouble,
    scope: scope,
  );

  static SettingKey<String> string(
    String name,
    String defaultValue, {
    SettingScope scope = SettingScope.synced,
  }) => SettingKey<String>(
    name,
    defaultValue: defaultValue,
    encode: _identity,
    decode: _decodeString,
    scope: scope,
  );

  static SettingKey<List<int>> intList(
    String name,
    List<int> defaultValue, {
    SettingScope scope = SettingScope.synced,
  }) => SettingKey<List<int>>(
    name,
    defaultValue: defaultValue,
    encode: _identity,
    decode: _decodeIntList,
    scope: scope,
  );

  static SettingKey<List<String>> stringList(
    String name,
    List<String> defaultValue, {
    SettingScope scope = SettingScope.synced,
  }) => SettingKey<List<String>>(
    name,
    defaultValue: defaultValue,
    encode: _identity,
    decode: _decodeStringList,
    scope: scope,
  );

  static SettingKey<Map<String, Object?>> jsonMap(
    String name, {
    Map<String, Object?> defaultValue = const {},
    SettingScope scope = SettingScope.synced,
  }) => SettingKey<Map<String, Object?>>(
    name,
    defaultValue: defaultValue,
    encode: _identity,
    decode: _decodeJsonMap,
    scope: scope,
  );

  final String name; // ^[a-z][a-zA-Z0-9_.]{0,63}$
  final T defaultValue;
  final Object? Function(T value) encode; // to JSON-compatible value
  final T Function(Object? json) decode; // may throw → default is used
  final SettingScope scope;

  @override
  String toString() => 'SettingKey<$T>($name, ${scope.name})';

  static Object? _identity(Object? v) => v;

  static bool _decodeBool(Object? j) => j! as bool;

  static int _decodeInt(Object? j) {
    if (j is int) return j;
    if (j is double && j == j.truncateToDouble() && j.isFinite) {
      return j.toInt();
    }
    throw FormatException('not an integer: $j');
  }

  // Real values also accept integers (web jsonEncode(1.0) == '1', 6.3).
  static double _decodeDouble(Object? j) => (j! as num).toDouble();

  static String _decodeString(Object? j) => j! as String;

  static List<int> _decodeIntList(Object? j) => List<int>.unmodifiable([
    for (final e in j! as List<Object?>) _decodeInt(e),
  ]);

  static List<String> _decodeStringList(Object? j) => List<String>.unmodifiable(
    [for (final e in j! as List<Object?>) e! as String],
  );

  static Map<String, Object?> _decodeJsonMap(Object? j) {
    final map = j! as Map<Object?, Object?>;
    return Map<String, Object?>.unmodifiable({
      for (final e in map.entries) e.key! as String: e.value,
    });
  }
}

@immutable
final class SettingsSnapshot {
  const SettingsSnapshot(this.raw);
  final Map<String, Object?> raw; // decoded JSON by key name (both scopes)

  /// Default when missing/undecodable.
  T get<T>(SettingKey<T> key) => decodeSetting(key, raw[key.name]);

  @override
  bool operator ==(Object other) =>
      other is SettingsSnapshot &&
      const DeepCollectionEquality().equals(other.raw, raw);

  @override
  int get hashCode => const DeepCollectionEquality().hash(raw);
}

abstract interface class SettingsRepository {
  Future<T> get<T>(SettingKey<T> key);
  Stream<T> watch<T>(SettingKey<T> key); // distinct values
  Future<void> set<T>(SettingKey<T> key, T value);
  Future<void> reset<T>(SettingKey<T> key);
  Stream<SettingsSnapshot> watchAll();
}
