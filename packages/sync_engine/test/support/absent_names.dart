// Names that must NOT be visible through any sync_engine entry point (07-sync 4.0, contract
// 00-overview 7.2.0 and 7.2.20 v1.1). test/api_surface_test.dart imports this library next to
// the four entry points without a prefix and refers to every name: if an entry point exported
// one of them, the reference would be ambiguous and the test would not compile.

/// Marker type of the absence checks.
final class Absent {
  const Absent();
}

// ── CORE names SYNC uses but never defines or re-exports (4.0, 5.1.1; contract 7.2.0) ──────
final class EntityKind {}

final class EntityRef {}

final class Hlc {}

final class HlcClock {}

final class OutboxOp {}

final class OutboxEntry {}

final class OutboxAck {}

const Absent kAllFields = Absent();

final class EntityFieldVersions {}

final class VersionedEntity {}

final class RemoteChange {}

final class RemoteUpsert {}

final class RemotePurge {}

final class MergeDecision {}

final class KeepLocal {}

final class TakeRemote {}

final class WriteMerged {}

final class RemoteMergePolicy {}

final class RemoteApplyReport {}

/// Also a removed SYNC port name (4.0 '1차'): CORE's typedef RepairWrite is used as is.
final class RepairWrite {}

final class SyncStore {}

final class AssetStore {}

final class Asset {}

final class AssetType {}

final class SyncEntity {}

final class EntityJson {}

/// Also a removed SYNC name (4.0 '1차'): CORE owns it (contract 7.2.13).
final class SyncDisplayState {}

final class SyncBadge {}

final class RemoteAssetFetcher {}

final class RemoteAssetState {}

final class RemoteAssetProgress {}

final class FolderId {}

final class NoteId {}

final class PageId {}

final class AssetId {}

final class OwnerId {}

final class EpochMillis {}

const Absent kLocalOwnerId = Absent();
const Absent noRetry = Absent();
const Absent noteStoreProvider = Absent();
const Absent clockProvider = Absent();

// ── SYNC names removed in revision 1 (4.0, contract 7.2.20 v1.1 '삭제') ────────────────────
const Absent syncDisplayStateProvider = Absent();
const Absent syncClockProvider = Absent();

final class FieldVersions {}

final class LocalRecord {}

final class AssetMeta {}

final class SyncMergeFn {}

final class MergeOutcome {}

final class KeepLocalOutcome {}

final class TakeRemoteOutcome {}

final class WriteMergedOutcome {}

final class LocalApplyReport {}

final class ApplyOutcomeKind {}

final class RepairReason {}

// ── Moved out of testing.dart in revision 2 (contract 7.2.20 v1.1 'testing.dart 정리') ─────
const Absent syncScenario = Absent();
const Absent expectConverged = Absent();

final class FakeAsync {}

// ── Internal files (4.2, 4.9 — not exported) ────────────────────────────────────────────
final class EntityFieldVersionsMerge {}

final class MergeRecorder {}

final class MergeOutcomeKind {}

final class EngineController {}

final class ChunkCodec {}

final class ChunkPacker {}

final class FieldMerge {}

final class RecordGate {}

final class StatusBuilder {}

final class EngineAssetService {}

final class AssetUploader {}

final class AssetDownloader {}

final class Compactor {}
