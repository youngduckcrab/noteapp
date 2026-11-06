/// Native storage path functions for `CoreModule(nativePaths: …)` in tests
/// (docs/plans/m5-7/01-infra.md 4.6.4, 6.9).
///
/// `flutter test` runs on the VM, where the default
/// resolveNativeStoragePaths is the native one: path_provider has no plugin
/// there, so it throws and CoreModule logs one record. Tests that count
/// error records or step timings pass [noNativePaths] (the web stub's
/// answer) or [fixedNativePaths].
library;

import 'dart:async';

import 'package:noteapp/src/storage/native_storage_paths.dart';

/// No native paths (what the web stub returns).
Future<NativeStoragePaths?> noNativePaths() async => null;

/// Always [paths]; counts its calls.
final class FixedNativePaths {
  FixedNativePaths(this.paths);

  final NativeStoragePaths? paths;
  int calls = 0;

  Future<NativeStoragePaths?> call() async {
    calls++;
    return paths;
  }
}

/// Throws [error] (a path_provider failure).
Future<NativeStoragePaths?> Function() failingNativePaths(Object error) =>
    () async => Error.throwWithStackTrace(error, StackTrace.current);

/// Completes when the test completes [gate] (resolving slowly).
Future<NativeStoragePaths?> Function() gatedNativePaths(
  Completer<NativeStoragePaths?> gate,
) =>
    () => gate.future;
