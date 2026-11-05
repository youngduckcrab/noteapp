// lib/src/assets/content_hasher.dart (internal) — SHA-256 of asset bytes (CORE 6.13 ①).
//
// Each file provides:
//   Future<String> sha256Hex(Uint8List bytes);   // lowercase hex, 64 chars = AssetId
// The web uses SubtleCrypto (package:crypto when it is missing, e.g. an insecure
// context); the VM and the stub use package:crypto.
export 'content_hasher_stub.dart'
    if (dart.library.js_interop) 'content_hasher_browser.dart'
    if (dart.library.ffi) 'content_hasher_native.dart';
