// Block keys (08-markdown 4.7, B-2): SHA-1 of a block's source (trimmed, LF) — first 8 hex
// characters — plus its ordinal among blocks with the same hash. Editing one block leaves
// every other block's key alone, so later pen notes per block (option ②) can anchor to
// them. v1 keeps them on screen only (never stored).
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Keys of the blocks whose sources are [sources], in order.
List<String> blockKeysOf(Iterable<String> sources) {
  final seen = <String, int>{};
  return [
    for (final s in sources)
      () {
        final hash = sha1
            .convert(utf8.encode(s.trim()))
            .toString()
            .substring(0, 8);
        final n = seen.update(hash, (v) => v + 1, ifAbsent: () => 0);
        return '$hash-$n';
      }(),
  ];
}
