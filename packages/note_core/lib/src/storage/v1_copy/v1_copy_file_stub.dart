// lib/src/storage/v1_copy/v1_copy_file_stub.dart (internal) — no files on this platform (web):
// the web copy is the canonical dump in the blob store (v1_copy.dart).
import 'package:drift/drift.dart';

Future<int> makeV1CopyFile(GeneratedDatabase db, String databasePath) =>
    Future.error(UnsupportedError('No database files on this platform'));

bool v1CopyFileExists(String databasePath) => false;

Stream<Uint8List> readV1CopyFile(String databasePath, int chunkBytes) =>
    Stream.error(UnsupportedError('No database files on this platform'));

Future<void> deleteV1CopyFiles(String databasePath) async {}
