// lib/src/assets/content_hasher_stub.dart (internal) — platforms without js_interop or
// ffi: package:crypto.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Future<String> sha256Hex(Uint8List bytes) async =>
    sha256.convert(bytes).toString();
