// Internal JSON readers for the CORE 6.3 wire format. Unknown keys are ignored
// by the callers; a missing required key or a wrong type is a FormatException.
// Real-valued fields accept integers too (web jsonEncode(1.0) == '1', 7.4.6).

Never _fail(String key, String expected, Object? value) =>
    throw FormatException(
      'JSON key "$key": expected $expected, got ${value.runtimeType}',
    );

Object? _required(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('JSON key "$key" is missing');
  }
  return json[key];
}

double asDouble(Object? value, String key) {
  if (value is num) return value.toDouble();
  _fail(key, 'number', value);
}

double readDouble(Map<String, Object?> json, String key) =>
    asDouble(_required(json, key), key);

double? readDoubleOrNull(Map<String, Object?> json, String key) {
  final v = json[key];
  return v == null ? null : asDouble(v, key);
}

double readDoubleOr(Map<String, Object?> json, String key, double fallback) =>
    readDoubleOrNull(json, key) ?? fallback;

int asInt(Object? value, String key) {
  if (value is int) return value;
  // Web: integers can arrive as doubles with no fraction.
  if (value is double && value == value.truncateToDouble() && value.isFinite) {
    return value.toInt();
  }
  _fail(key, 'integer', value);
}

int readInt(Map<String, Object?> json, String key) =>
    asInt(_required(json, key), key);

int? readIntOrNull(Map<String, Object?> json, String key) {
  final v = json[key];
  return v == null ? null : asInt(v, key);
}

String asString(Object? value, String key) {
  if (value is String) return value;
  _fail(key, 'string', value);
}

String readString(Map<String, Object?> json, String key) =>
    asString(_required(json, key), key);

String? readStringOrNull(Map<String, Object?> json, String key) {
  final v = json[key];
  return v == null ? null : asString(v, key);
}

bool readBool(Map<String, Object?> json, String key) {
  final v = _required(json, key);
  if (v is bool) return v;
  _fail(key, 'bool', v);
}

bool readBoolOr(Map<String, Object?> json, String key, bool fallback) {
  final v = json[key];
  if (v == null) return fallback;
  if (v is bool) return v;
  _fail(key, 'bool', v);
}

Map<String, Object?> asMap(Object? value, String key) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    final out = <String, Object?>{};
    for (final e in value.entries) {
      final k = e.key;
      if (k is! String) _fail(key, 'object with string keys', value);
      out[k] = e.value;
    }
    return out;
  }
  _fail(key, 'object', value);
}

Map<String, Object?> readMap(Map<String, Object?> json, String key) =>
    asMap(_required(json, key), key);

Map<String, Object?>? readMapOrNull(Map<String, Object?> json, String key) {
  final v = json[key];
  return v == null ? null : asMap(v, key);
}

List<Object?> asList(Object? value, String key) {
  if (value is List<Object?>) return value;
  _fail(key, 'array', value);
}

List<Object?> readList(Map<String, Object?> json, String key) =>
    asList(_required(json, key), key);

/// A JSON-safe deep copy of an `extras` map (String keys, nested maps/lists).
Map<String, Object?> readExtras(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return const {};
  return Map<String, Object?>.unmodifiable(asMap(v, key));
}

// --- (v2.0) 2nd-round page object JSON (m5-7/02-core 6.2.6, 6.3) ---

/// A known object type carrying an enum name this app does not know (`shape`, `dash`,
/// `arrowHeads`, `align` — 02-core 6.2.6, CP-6). PageObject.fromJson reads the whole object as
/// UnknownObject instead of dropping it; a direct style / geometry read reports it as a
/// FormatException (this type).
final class UnknownEnumNameException extends FormatException {
  UnknownEnumNameException(this.key, this.name)
    : super('JSON key "$key": unknown name "$name"');
  final String key;
  final String name;
}

/// The enum value named by `json[key]`; [fallback] when the key is absent or null.
T readEnumOr<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
  T fallback,
) {
  final v = json[key];
  if (v == null) return fallback;
  return enumByName(asString(v, key), key, values);
}

/// The enum value named by the required string `json[key]`.
T readEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
) => enumByName(readString(json, key), key, values);

T enumByName<T extends Enum>(String name, String key, List<T> values) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw UnknownEnumNameException(key, name);
}

/// A finite number (FormatException for NaN / infinity — local maps can carry them).
double asFiniteDouble(Object? value, String key) {
  final d = asDouble(value, key);
  if (!d.isFinite) {
    throw FormatException('JSON key "$key": expected a finite number, got $d');
  }
  return d;
}

/// `[n0, n1, …]` of finite numbers.
List<double> asFiniteDoubles(Object? value, String key) => [
  for (final e in asList(value, key)) asFiniteDouble(e, key),
];

/// A list of strings (each element checked).
List<String> asStrings(Object? value, String key) => [
  for (final e in asList(value, key)) asString(e, key),
];

/// An unmodifiable deep copy of a JSON value: null, bool, num, String, List, Map with String
/// keys. Anything else is a FormatException (UnknownObject keeps rawJson this way — C-12).
Object? jsonDeepCopy(Object? value, String key) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable([
      for (final e in value) jsonDeepCopy(e, key),
    ]);
  }
  if (value is Map) {
    final out = <String, Object?>{};
    for (final e in value.entries) {
      final k = e.key;
      if (k is! String) _fail(key, 'object with string keys', value);
      out[k] = jsonDeepCopy(e.value, key);
    }
    return Map<String, Object?>.unmodifiable(out);
  }
  _fail(key, 'JSON value', value);
}
