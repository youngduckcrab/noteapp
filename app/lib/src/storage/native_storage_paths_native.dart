/// Native side of [resolveNativeStoragePaths] (docs/plans/m5-7/01-infra.md
/// 4.6.3, 6.9 — Android `Context.getFilesDir()`, iOS
/// `Library/Application Support/`, unconfirmed on a device: A-1).
library;

import 'dart:io' show Directory;

import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

import 'native_storage_paths_types.dart';

/// Name of the app's own folder under the application support directory.
const String _folder = 'noteapp';

/// path_provider getApplicationSupportDirectory(), creates
/// `<support>/noteapp/` (recursive) and returns
/// NativeStoragePaths with `<support>/noteapp/noteapp.sqlite` and
/// `<support>/noteapp/assets`. The `assets/` directory and the files are
/// CORE's (contract 7.2.6 v2.1 — CORE creates a missing blob root).
///
/// Throws on failure (no support directory, a channel error, the folder
/// cannot be created): CoreModule logs it and opens without paths → CORE
/// storageUnavailable → the startup error screen.
Future<NativeStoragePaths?> resolveNativeStoragePaths() async {
  final support = await getApplicationSupportDirectory();
  final base = support.path.endsWith('/')
      ? support.path.substring(0, support.path.length - 1)
      : support.path;
  final root = '$base/$_folder';
  await Directory(root).create(recursive: true);
  return NativeStoragePaths(
    databasePath: '$root/noteapp.sqlite',
    assetDirectoryPath: '$root/assets',
  );
}
