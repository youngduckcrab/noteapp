// Internal (not exported). Canonical JSON (6.4.4): keys sorted at every level, no
// whitespace, dart:convert jsonEncode for scalar values.
import 'dart:convert';
import 'dart:typed_data';

/// Canonical text of a JSON value (Map with String keys, List, String, num, bool, null).
/// ArgumentError for any other value or a non-String map key.
String canonicalJson(Object? value) {
  final out = StringBuffer();
  _write(out, value);
  return out.toString();
}

/// UTF-8 bytes of [canonicalJson].
Uint8List canonicalJsonBytes(Object? value) =>
    utf8.encode(canonicalJson(value));

void _write(StringBuffer out, Object? value) {
  switch (value) {
    case null || bool() || num() || String():
      if (value is double && !value.isFinite) {
        throw ArgumentError.value(value, 'value', 'not a JSON number');
      }
      out.write(jsonEncode(value));
    case Map<Object?, Object?>():
      final keys = <String>[];
      for (final k in value.keys) {
        if (k is! String) {
          throw ArgumentError.value(k, 'key', 'JSON keys must be strings');
        }
        keys.add(k);
      }
      keys.sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out
          ..write(jsonEncode(keys[i]))
          ..write(':');
        _write(out, value[keys[i]]);
      }
      out.write('}');
    case List<Object?>():
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) out.write(',');
        _write(out, value[i]);
      }
      out.write(']');
    default:
      throw ArgumentError.value(value, 'value', 'not a JSON value');
  }
}
