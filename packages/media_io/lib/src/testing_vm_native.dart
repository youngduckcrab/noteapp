// lib/src/testing_vm_native.dart — testing_vm_factory.dart on the VM (dart:io): the temp
// directory installFakeMediaPlatforms gives media_io's hooks instead of path_provider, and
// the file FakeRecordPlatform.stop() "finishes". testing.dart only (tests).
import 'dart:io';
import 'dart:typed_data';

/// A new temporary directory (Directory.systemTemp/media_io_test_*) and a function that
/// deletes it with everything in it (idempotent).
({String path, void Function() delete})? createMediaTestDirectory() {
  final dir = Directory.systemTemp.createTempSync('media_io_test_');
  return (
    path: dir.path,
    delete: () {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    },
  );
}

/// Writes [bytes] to the file at [path], creating its parent directories.
void writeMediaTestFile(String path, Uint8List bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes, flush: true);
}
