// package:note_core/testing_web.dart — (v2.1) browser tests only (test/web/, Chrome)
// Contract comments are kept verbatim (they contain <placeholders>).
// ignore_for_file: unintended_html_in_doc_comment
/// Browser-test helper of note_core (2nd-round contract 7.1 / 7.6, C2-39; m5-7/02-core 4.9,
/// 6.18.1). Import from `test/web/` only (INFRA R4 exception — lib_exceptions). The helpers
/// work from CORE T23b on (m5-7/02-core 8.1 'B2 상태').
library;

import 'src/common/pending.dart';
import 'src/repo/note_store.dart';

/// The REAL web store (IndexedDB + drift web worker) under a unique [name]; needs the files of
/// CORE's tool/prepare_web_test.dart. For PDF V8 / V16 / V11 and CORE's own browser tests.
///
/// CORE 4.9: databaseName 'webtest_<name>', blobs 'webtest_<name>_blobs', WebStorageConfig
/// default asset URLs (sqlite3.wasm, drift_worker.js next to the test page), the stored HLC
/// node (a new random one for a new database — as openNoteStore), requestPersistentStorage
/// false. Opening the same name again reopens the same data (V16 '새 컨테이너'). [name] must
/// match ^[A-Za-z0-9_-]{1,40}$ (ArgumentError otherwise).
Future<NoteStore> openWebTestNoteStore(String name) async =>
    notYet('T23b', 'openWebTestNoteStore');

/// CORE 4.9: deleteLocalNoteData of that config (the store must be closed).
Future<void> deleteWebTestNoteStore(String name) async =>
    notYet('T23b', 'deleteWebTestNoteStore');
