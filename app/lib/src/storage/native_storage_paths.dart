/// Native storage paths of the app shell (docs/plans/m5-7/01-infra.md 4.6.3,
/// 6.9). The web build gets the stub (null — CORE keeps its IndexedDB
/// storage); only `native_storage_paths_native.dart` imports
/// package:path_provider (workspace rule R4 `native_only_imports`).
library;

export 'native_storage_paths_stub.dart'
    if (dart.library.io) 'native_storage_paths_native.dart'
    show resolveNativeStoragePaths;
export 'native_storage_paths_types.dart' show NativeStoragePaths;
