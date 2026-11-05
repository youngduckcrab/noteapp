import 'package:meta/meta.dart';

import 'assets/sync_asset_service.dart';

enum DevicePlatform { web, ios, android, other }

@immutable
final class CompactionConfig {
  const CompactionConfig({
    this.enabled = true,
    this.minChunksPerScope = 400,
    this.minInterval = const Duration(hours: 24),
    this.startJitterMax = const Duration(seconds: 60),
    this.maxScopeBytes = 64 * 1024 * 1024,
  });
  final bool enabled;

  /// Chunks seen in a scope since its last compaction.
  final int minChunksPerScope;

  /// Per scope, per device.
  final Duration minInterval;

  /// Random delay before starting (reduces concurrent runs).
  final Duration startJitterMax;

  /// Skip scopes larger than this (memory on iPad Safari).
  final int maxScopeBytes;
}

@immutable
final class SyncConfig {
  const SyncConfig({
    this.appVersion = '0.0.0',
    this.platform = DevicePlatform.web,
    this.debounce = const Duration(milliseconds: 500),
    this.maxBatchDelay = const Duration(milliseconds: 1000),
    this.maxEntriesPerPush = 500,
    this.chunkSoftLimitBytes = 256 * 1024,
    this.chunkHardLimitBytes = 1000000,
    this.maxRecordsPerChunk = 2000,
    this.maxChunksPerCommit = 16,
    this.maxBytesPerCommit = 8 * 1024 * 1024,
    this.maxBisectSteps = 32,
    this.fetchPageSize = 50,
    this.maxRecordsPerApply = 2000,
    this.maxBytesPerApply = 8 * 1024 * 1024,
    this.cursorOverlap = const Duration(minutes: 5),
    this.listenerRolloverChunks = 500,
    this.listenerRolloverInterval = const Duration(minutes: 15),
    this.listenerRolloverOverlap = const Duration(seconds: 60),
    this.appliedChunkMemory = 4096,
    this.backoffBase = const Duration(seconds: 1),
    this.backoffMax = const Duration(seconds: 60),
    this.backoffJitter = 0.2,
    this.offlineAfterFailures = 2,
    this.offlineProbeInterval = const Duration(seconds: 30),
    this.quotaBackoff = const Duration(minutes: 5),
    this.misconfiguredBackoff = const Duration(minutes: 10),
    this.operationTimeout = const Duration(seconds: 30),
    this.reconnectAfterBackground = const Duration(seconds: 30),
    this.backgroundFlushTimeout = const Duration(seconds: 5),
    this.cycleRepairGrace = const Duration(seconds: 10),
    this.purgeGuardWindow = const Duration(minutes: 10),
    this.clockSkewWarning = const Duration(minutes: 2),
    this.clockSkewLimit = const Duration(
      hours: 24,
    ), // = CORE HlcClock.maxForwardDrift (7.2.10)
    this.clockSkewRecheck = const Duration(minutes: 5),
    this.futureRecordMargin = const Duration(minutes: 1),
    this.maxHeldChunks = 2000,
    this.statusThrottle = const Duration(milliseconds: 250),
    this.deviceHeartbeat = const Duration(hours: 1),
    this.maxAssetUploadBytes = 300 * 1024 * 1024,
    this.maxAssetDownloadBytes = 512 * 1024 * 1024,
    this.assetUploadConcurrency = 1,
    this.assetDownloadConcurrency = 2,
    this.assetPrefetch = AssetPrefetchPolicy.onDemand,
    this.compaction = const CompactionConfig(),
    this.recoveredNoteTitleSuffix = ' (동기화 복구)', // approved (12.1 Q14)
  });
  final String appVersion;
  final DevicePlatform platform;
  final Duration debounce;
  final Duration maxBatchDelay;
  final int maxEntriesPerPush;
  final int chunkSoftLimitBytes;
  final int chunkHardLimitBytes;
  final int maxRecordsPerChunk;
  final int maxChunksPerCommit;
  final int maxBytesPerCommit;
  final int maxBisectSteps;
  final int fetchPageSize;
  final int maxRecordsPerApply;
  final int maxBytesPerApply;
  final Duration cursorOverlap;
  final int listenerRolloverChunks;
  final Duration listenerRolloverInterval;
  final Duration listenerRolloverOverlap;
  final int appliedChunkMemory;
  final Duration backoffBase;
  final Duration backoffMax;
  final double backoffJitter;
  final int offlineAfterFailures;
  final Duration offlineProbeInterval;
  final Duration quotaBackoff;
  final Duration misconfiguredBackoff;
  final Duration operationTimeout;
  final Duration reconnectAfterBackground;
  final Duration backgroundFlushTimeout;
  final Duration cycleRepairGrace;
  final Duration purgeGuardWindow;
  final Duration clockSkewWarning;
  final Duration clockSkewLimit;
  final Duration clockSkewRecheck;
  final Duration futureRecordMargin;
  final int maxHeldChunks;
  final Duration statusThrottle;
  final Duration deviceHeartbeat;
  final int maxAssetUploadBytes;
  final int maxAssetDownloadBytes;
  final int assetUploadConcurrency;
  final int assetDownloadConcurrency;
  final AssetPrefetchPolicy assetPrefetch;
  final CompactionConfig compaction;
  final String recoveredNoteTitleSuffix;

  SyncConfig copyWith({
    String? appVersion,
    DevicePlatform? platform,
    Duration? debounce,
    Duration? maxBatchDelay,
    int? maxEntriesPerPush,
    int? chunkSoftLimitBytes,
    int? chunkHardLimitBytes,
    int? maxRecordsPerChunk,
    int? maxChunksPerCommit,
    int? maxBytesPerCommit,
    int? maxBisectSteps,
    int? fetchPageSize,
    int? maxRecordsPerApply,
    int? maxBytesPerApply,
    Duration? cursorOverlap,
    int? listenerRolloverChunks,
    Duration? listenerRolloverInterval,
    Duration? listenerRolloverOverlap,
    int? appliedChunkMemory,
    Duration? backoffBase,
    Duration? backoffMax,
    double? backoffJitter,
    int? offlineAfterFailures,
    Duration? offlineProbeInterval,
    Duration? quotaBackoff,
    Duration? misconfiguredBackoff,
    Duration? operationTimeout,
    Duration? reconnectAfterBackground,
    Duration? backgroundFlushTimeout,
    Duration? cycleRepairGrace,
    Duration? purgeGuardWindow,
    Duration? clockSkewWarning,
    Duration? clockSkewLimit,
    Duration? clockSkewRecheck,
    Duration? futureRecordMargin,
    int? maxHeldChunks,
    Duration? statusThrottle,
    Duration? deviceHeartbeat,
    int? maxAssetUploadBytes,
    int? maxAssetDownloadBytes,
    int? assetUploadConcurrency,
    int? assetDownloadConcurrency,
    AssetPrefetchPolicy? assetPrefetch,
    CompactionConfig? compaction,
    String? recoveredNoteTitleSuffix,
  }) => SyncConfig(
    appVersion: appVersion ?? this.appVersion,
    platform: platform ?? this.platform,
    debounce: debounce ?? this.debounce,
    maxBatchDelay: maxBatchDelay ?? this.maxBatchDelay,
    maxEntriesPerPush: maxEntriesPerPush ?? this.maxEntriesPerPush,
    chunkSoftLimitBytes: chunkSoftLimitBytes ?? this.chunkSoftLimitBytes,
    chunkHardLimitBytes: chunkHardLimitBytes ?? this.chunkHardLimitBytes,
    maxRecordsPerChunk: maxRecordsPerChunk ?? this.maxRecordsPerChunk,
    maxChunksPerCommit: maxChunksPerCommit ?? this.maxChunksPerCommit,
    maxBytesPerCommit: maxBytesPerCommit ?? this.maxBytesPerCommit,
    maxBisectSteps: maxBisectSteps ?? this.maxBisectSteps,
    fetchPageSize: fetchPageSize ?? this.fetchPageSize,
    maxRecordsPerApply: maxRecordsPerApply ?? this.maxRecordsPerApply,
    maxBytesPerApply: maxBytesPerApply ?? this.maxBytesPerApply,
    cursorOverlap: cursorOverlap ?? this.cursorOverlap,
    listenerRolloverChunks:
        listenerRolloverChunks ?? this.listenerRolloverChunks,
    listenerRolloverInterval:
        listenerRolloverInterval ?? this.listenerRolloverInterval,
    listenerRolloverOverlap:
        listenerRolloverOverlap ?? this.listenerRolloverOverlap,
    appliedChunkMemory: appliedChunkMemory ?? this.appliedChunkMemory,
    backoffBase: backoffBase ?? this.backoffBase,
    backoffMax: backoffMax ?? this.backoffMax,
    backoffJitter: backoffJitter ?? this.backoffJitter,
    offlineAfterFailures: offlineAfterFailures ?? this.offlineAfterFailures,
    offlineProbeInterval: offlineProbeInterval ?? this.offlineProbeInterval,
    quotaBackoff: quotaBackoff ?? this.quotaBackoff,
    misconfiguredBackoff: misconfiguredBackoff ?? this.misconfiguredBackoff,
    operationTimeout: operationTimeout ?? this.operationTimeout,
    reconnectAfterBackground:
        reconnectAfterBackground ?? this.reconnectAfterBackground,
    backgroundFlushTimeout:
        backgroundFlushTimeout ?? this.backgroundFlushTimeout,
    cycleRepairGrace: cycleRepairGrace ?? this.cycleRepairGrace,
    purgeGuardWindow: purgeGuardWindow ?? this.purgeGuardWindow,
    clockSkewWarning: clockSkewWarning ?? this.clockSkewWarning,
    clockSkewLimit: clockSkewLimit ?? this.clockSkewLimit,
    clockSkewRecheck: clockSkewRecheck ?? this.clockSkewRecheck,
    futureRecordMargin: futureRecordMargin ?? this.futureRecordMargin,
    maxHeldChunks: maxHeldChunks ?? this.maxHeldChunks,
    statusThrottle: statusThrottle ?? this.statusThrottle,
    deviceHeartbeat: deviceHeartbeat ?? this.deviceHeartbeat,
    maxAssetUploadBytes: maxAssetUploadBytes ?? this.maxAssetUploadBytes,
    maxAssetDownloadBytes: maxAssetDownloadBytes ?? this.maxAssetDownloadBytes,
    assetUploadConcurrency:
        assetUploadConcurrency ?? this.assetUploadConcurrency,
    assetDownloadConcurrency:
        assetDownloadConcurrency ?? this.assetDownloadConcurrency,
    assetPrefetch: assetPrefetch ?? this.assetPrefetch,
    compaction: compaction ?? this.compaction,
    recoveredNoteTitleSuffix:
        recoveredNoteTitleSuffix ?? this.recoveredNoteTitleSuffix,
  );
}
