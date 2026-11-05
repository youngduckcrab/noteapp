// lib/src/assets/content_hasher_native.dart (internal) — VM and native: package:crypto
// only (no dart:io).
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Future<String> sha256Hex(Uint8List bytes) async =>
    sha256.convert(bytes).toString();
