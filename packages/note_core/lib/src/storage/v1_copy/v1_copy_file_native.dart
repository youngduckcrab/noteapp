// lib/src/storage/v1_copy/v1_copy_file_native.dart (internal) — the v1 copy as a SQLite file
// next to the database file (m5-7/02-core 6.12.4). VACUUM INTO refuses an existing target,
// so a left-over temporary file is deleted first; the finished copy replaces an older one.
import 'dart:io';

import 'package:drift/drift.dart';

import 'v1_copy_file.dart';

Future<int> makeV1CopyFile(GeneratedDatabase db, String databasePath) async {
  final tmp = File(v1CopyTempPathOf(databasePath));
  if (tmp.existsSync()) await tmp.delete();
  await db.customStatement('VACUUM INTO ?', [tmp.path]);
  final target = File(v1CopyPathOf(databasePath));
  if (target.existsSync()) await target.delete();
  final done = await tmp.rename(target.path);
  return done.length();
}

bool v1CopyFileExists(String databasePath) =>
    File(v1CopyPathOf(databasePath)).existsSync();

Stream<Uint8List> readV1CopyFile(String databasePath, int chunkBytes) async* {
  final file = await File(v1CopyPathOf(databasePath)).open();
  try {
    while (true) {
      final chunk = await file.read(chunkBytes);
      if (chunk.isEmpty) break;
      yield chunk;
    }
  } finally {
    await file.close();
  }
}

Future<void> deleteV1CopyFiles(String databasePath) async {
  for (final p in [
    v1CopyPathOf(databasePath),
    v1CopyTempPathOf(databasePath),
  ]) {
    final f = File(p);
    if (f.existsSync()) await f.delete();
  }
}
