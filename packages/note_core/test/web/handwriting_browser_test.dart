// CORE T32 — the handwriting contract (m5-7/02-core 6.9, test/shared/handwriting_contract.dart)
// on the real web store (sqlite3.wasm in a worker): the pages.ink_rev refresh joins the input
// strokes with an aggregate ORDER BY and writes the cache with UPDATE … FROM (VALUES …) — both
// must run on the wasm build as on the VM (6.9.3).
@TestOn('browser')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/testing_web.dart';
import 'package:test/test.dart';

import '../shared/handwriting_contract.dart';

var _serial = 0;
String _name(String tag) =>
    'core_t32_${tag}_${DateTime.now().microsecondsSinceEpoch}_${_serial++}';

void main() {
  String? name;
  tearDown(() async {
    if (name case final n?) await deleteWebTestNoteStore(n);
    name = null;
  });

  group('shared body', () {
    defineHandwritingContract(() async {
      final n = name = _name('hw');
      final NoteStore store = await openWebTestNoteStore(n);
      return store;
    });
  });
}
