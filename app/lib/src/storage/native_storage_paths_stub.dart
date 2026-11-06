/// Web / stub side of [resolveNativeStoragePaths] (docs/plans/m5-7/
/// 01-infra.md 4.6.3).
library;

import 'native_storage_paths_types.dart';

/// Web / stub: null (CORE opens its web storage; the shell passes no native
/// path — the same as the 1st round).
Future<NativeStoragePaths?> resolveNativeStoragePaths() async => null;
