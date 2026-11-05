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
