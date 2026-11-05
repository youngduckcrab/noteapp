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
/// Exports the 4.1 ~ 4.9 signature files (07-sync 4.0 table). Internal files
/// (field_versions_ext.dart, merge_recorder.dart, engine internals) are not
/// exported.
library;

export 'src/assets/sync_asset_service.dart';
export 'src/assets/sync_remote_asset_fetcher.dart';
export 'src/auth/auth_backend.dart';
export 'src/auth/auth_service.dart';
export 'src/auth/auth_user.dart';
export 'src/backend/blob_store.dart';
export 'src/backend/profile.dart';
export 'src/backend/remote_chunk.dart';
export 'src/backend/sync_backend.dart';
export 'src/common/cancel_token.dart';
export 'src/common/errors.dart';
export 'src/common/server_cursor.dart';
export 'src/config.dart';
export 'src/engine/connectivity.dart';
export 'src/engine/sync_engine.dart';
export 'src/local/core_sync_local_store.dart';
export 'src/local/sync_local_store.dart';
export 'src/merge/sync_merge_policy.dart';
export 'src/model/field_units.dart';
export 'src/model/records.dart';
export 'src/model/scopes.dart';
export 'src/model/sync_doc.dart';
export 'src/providers.dart';
export 'src/status/sync_badge.dart';
export 'src/status/sync_issue.dart';
export 'src/status/sync_notice.dart';
export 'src/status/sync_status.dart';
