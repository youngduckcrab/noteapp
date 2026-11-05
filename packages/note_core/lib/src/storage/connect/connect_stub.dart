// lib/src/storage/connect/connect_stub.dart (internal) — platforms without storage.
import 'package:drift/drift.dart';

import '../../common/errors.dart';
import '../../repo/note_store.dart';
import '../../repo/status.dart';

Future<(QueryExecutor, StorageInfo)> openNoteDatabaseExecutor(
  NoteStoreConfig config,
) async => throw const NoteStoreOpenException(
  NoteStoreOpenFailure.storageUnavailable,
  'Local storage is not supported on this platform.',
);

Future<void> deleteLocalData(NoteStoreConfig config) async {}
