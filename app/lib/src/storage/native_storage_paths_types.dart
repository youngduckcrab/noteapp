/// The two native storage paths handed to CORE (docs/plans/m5-7/01-infra.md
/// 4.6.3, 6.9; contract 00-overview 7.2.6 / 7.2.12 v2.1 — 공통-1).
library;

import 'package:flutter/foundation.dart' show immutable;

/// Where the native app keeps its notes: one SQLite file and the blob root
/// directory, both under `<application support>/noteapp/` (the same volume —
/// CORE renames temporary files inside one directory only).
///
/// CoreModule publishes it; defaultNoteStoreConfig sets BOTH
/// NoteStoreConfig.nativeDatabasePath and nativeAssetDirectoryPath from it
/// (contract 7.2.6 — both or neither).
@immutable
final class NativeStoragePaths {
  const NativeStoragePaths({
    required this.databasePath,
    required this.assetDirectoryPath,
  });

  /// `<support>/noteapp/noteapp.sqlite`.
  final String databasePath;

  /// `<support>/noteapp/assets` (CORE creates it when missing).
  final String assetDirectoryPath;

  @override
  bool operator ==(Object other) =>
      other is NativeStoragePaths &&
      other.databasePath == databasePath &&
      other.assetDirectoryPath == assetDirectoryPath;

  @override
  int get hashCode => Object.hash(databasePath, assetDirectoryPath);

  @override
  String toString() =>
      'NativeStoragePaths(databasePath: $databasePath, '
      'assetDirectoryPath: $assetDirectoryPath)';
}
