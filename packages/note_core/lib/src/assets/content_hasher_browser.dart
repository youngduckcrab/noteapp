// lib/src/assets/content_hasher_browser.dart (internal) — web: SubtleCrypto digest,
// package:crypto when crypto.subtle is missing (insecure context, 6.13 ①).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web/web.dart' as web;

Future<String> sha256Hex(Uint8List bytes) async {
  final subtle = subtleCrypto();
  if (subtle == null) return sha256.convert(bytes).toString();
  final result = await subtle.digest('SHA-256'.toJS, bytes.toJS).toDart;
  return hexOf((result! as JSArrayBuffer).toDart.asUint8List());
}

/// globalThis.crypto.subtle, or null where the page cannot use it.
web.SubtleCrypto? subtleCrypto() {
  final crypto = globalContext['crypto'];
  if (crypto == null || crypto.isUndefinedOrNull) return null;
  final subtle = (crypto as JSObject)['subtle'];
  if (subtle == null || subtle.isUndefinedOrNull) return null;
  return subtle as web.SubtleCrypto;
}

/// Lowercase hex of [digest] (arithmetic only, web-safe numbers 7.4.3).
String hexOf(Uint8List digest) {
  final out = StringBuffer();
  for (final b in digest) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}
