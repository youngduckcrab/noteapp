/// Account and sync engine of noteapp (contract 00-overview 7.2.20, 07-sync
/// 4.1 ~ 4.9): `SyncEngine`, `SyncStatus`, `SyncIssue`, `SyncNotice`,
/// `AuthService`, `SyncAssetService`, `SyncConfig`, the providers,
/// `syncBadgeOf`, `SyncRemoteAssetFetcher` and `SyncMergePolicy`. CORE types
/// are used from `package:note_core/note_core.dart` and never re-exported
/// (contract 7.2.0).
///
/// Pure Dart: this library and everything it imports or exports, directly or
/// transitively, never imports Flutter, Firebase, connectivity_plus or
/// `package:web` (contract 7.1, 07-sync 3.1). `test/no_dart_io_test.dart`
/// checks this.
///
/// Foundation step B7 (00-overview 7.6): empty frame. The exports are added
/// during concurrent development, starting with SYNC T1 (07-sync 8).
library;
