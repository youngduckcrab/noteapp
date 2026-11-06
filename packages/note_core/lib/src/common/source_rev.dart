// lib/src/common/source_rev.dart (internal) — the sourceRev hash of m5-7/02-core 6.9.2, shared
// by HandwritingText.sourceRevOf (Stroke values) and the SQLite store's pages.ink_rev cache
// (stroke rows read without their points — 6.9.3).
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// sourceRev of the empty input (the empty string's SHA-256, first 16 hex chars).
const String kEmptySourceRev = 'e3b0c44298fc1c14';

/// Sorted by id with String.compareTo (UTF-16 order — the same on the VM and the web),
/// `"<id>:<updatedAt>;"` joined, SHA-256 of the UTF-8 bytes, lowercase hex, first 16 chars.
String sourceRevOfPairs(Iterable<(String id, int updatedAt)> strokes) {
  final sorted = strokes.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  final text = StringBuffer();
  for (final (id, updatedAt) in sorted) {
    text
      ..write(id)
      ..write(':')
      ..write(updatedAt)
      ..write(';');
  }
  return sourceRevOfJoined(text.toString());
}

/// The hash step of [sourceRevOfPairs] over the already joined `"<id>:<updatedAt>;…"` text
/// (the SQLite store joins it in SQL: entity ids are ASCII — isValidEntityId — so SQLite's
/// BINARY order is String.compareTo order).
String sourceRevOfJoined(String joined) =>
    sha256.convert(utf8.encode(joined)).toString().substring(0, 16);
