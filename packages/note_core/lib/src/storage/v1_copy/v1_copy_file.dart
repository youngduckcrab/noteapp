// lib/src/storage/v1_copy/v1_copy_file.dart (internal) — the native file form of the v1
// database copy (m5-7/02-core 6.12.4: VACUUM INTO '<path>-v1-backup.tmp' → rename).
//
// Each file provides:
//   Future<int> makeV1CopyFile(GeneratedDatabase db, String databasePath);  // bytes
//   bool v1CopyFileExists(String databasePath);
//   Stream<Uint8List> readV1CopyFile(String databasePath, int chunkBytes);
//   Future<void> deleteV1CopyFiles(String databasePath);  // the copy and its .tmp
export 'v1_copy_file_stub.dart'
    if (dart.library.ffi) 'v1_copy_file_native.dart';

/// The copy file of the database file [databasePath] (6.12.4 name).
String v1CopyPathOf(String databasePath) => '$databasePath-v1-backup';

/// The file VACUUM INTO writes before it is renamed to [v1CopyPathOf].
String v1CopyTempPathOf(String databasePath) =>
    '${v1CopyPathOf(databasePath)}.tmp';
