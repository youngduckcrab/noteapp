// lib/src/testing_vm_stub.dart — testing_vm_factory.dart off the VM: nothing (the media_io
// platform fakes are VM only — installFakeMediaPlatforms asserts !kIsWeb).
import 'dart:typed_data';

/// A temporary directory for one installFakeMediaPlatforms; null where there is no file
/// system.
({String path, void Function() delete})? createMediaTestDirectory() => null;

/// Writes [bytes] to the file at [path] (FakeRecordPlatform.stop); nothing here.
void writeMediaTestFile(String path, Uint8List bytes) {}
