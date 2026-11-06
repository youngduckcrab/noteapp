// lib/src/storage/connect/connect_stub.dart (internal) — platforms without storage.
import 'package:drift/drift.dart';
import 'package:idb_shim/idb_client_memory.dart';

import '../../assets/blob_store.dart';
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

IdbFactory blobIdbFactory(NoteStoreConfig config) => newIdbFactoryMemory();

/// (v2) No file blobs here (6.15.3 — native only).
Future<BlobDatabase?> openFileBlobDatabase(NoteStoreConfig config) async =>
    null;
