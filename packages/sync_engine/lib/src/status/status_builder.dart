// Internal (not exported). SyncStatus from the engine's inputs (6.12): the display table, the
// active issues (blocking first) and the publishing rule — phase or display changes go out at
// once, anything else (pending counts, progress, issue counters) at most once per
// statusThrottle; a value equal (==) to the last published one is never published again.
import 'dart:async';

import 'package:note_core/note_core.dart';

import '../auth/auth_user.dart';
import 'sync_issue.dart';
import 'sync_status.dart';

final class StatusBuilder {
  StatusBuilder({
    required this._phase,
    required this.throttle,
    required this.nowMillis,
  }) {
    _current = _build();
    _published = _current;
  }

  /// SyncConfig.statusThrottle (250 ms).
  final Duration throttle;

  /// The engine wall clock (issue firstAt / lastAt).
  final int Function() nowMillis;

  SyncPhase _phase;
  AuthUser? _user;
  int _pendingUploads = 0;
  int _quarantinedUploads = 0;
  bool _isPushing = false;
  InitialSyncProgress? _initialSync;
  AssetTransferSummary _assets = AssetTransferSummary.idle;
  int? _lastSyncedAt;
  int? _nextRetryAt;
  bool _isOnline = true;
  Duration? _clockSkew;

  /// Active issues by key, in the order they were first raised.
  final Map<String, SyncIssue> _issues = {};

  late SyncStatus _current;
  late SyncStatus _published;
  final StreamController<SyncStatus> _out = StreamController.broadcast();
  Timer? _cooldown;
  bool _dirty = false;
  bool _closed = false;

  /// The status now (may be newer than the last published one while throttled).
  SyncStatus get status => _current;

  /// Published values (throttled, distinct). Broadcast; no replay.
  Stream<SyncStatus> get published => _out.stream;

  /// 6.12, first match from the top.
  static SyncDisplayState displayOf({
    required SyncPhase phase,
    required bool hasBlockingIssue,
    required int quarantinedUploads,
    required int pendingUploads,
    required bool isPushing,
    required AssetTransferSummary assets,
  }) {
    if (phase == SyncPhase.disabled ||
        phase == SyncPhase.signedOut ||
        phase == SyncPhase.paused) {
      return SyncDisplayState.off;
    }
    if (hasBlockingIssue || quarantinedUploads > 0) {
      return SyncDisplayState.error;
    }
    if (phase == SyncPhase.offline) return SyncDisplayState.offline;
    if (phase == SyncPhase.connecting ||
        phase == SyncPhase.initialSync ||
        phase == SyncPhase.catchingUp ||
        pendingUploads > 0 ||
        isPushing ||
        assets.uploadsPending > 0 ||
        assets.uploadBytesTotal > assets.uploadBytesDone) {
      return SyncDisplayState.inProgress;
    }
    return SyncDisplayState.done;
  }

  // ---- inputs ---------------------------------------------------------------------------

  SyncPhase get phase => _phase;
  set phase(SyncPhase v) => _set(() => _phase = v);

  AuthUser? get user => _user;
  set user(AuthUser? v) => _set(() => _user = v);

  int get pendingUploads => _pendingUploads;
  set pendingUploads(int v) => _set(() => _pendingUploads = v);

  int get quarantinedUploads => _quarantinedUploads;
  set quarantinedUploads(int v) => _set(() => _quarantinedUploads = v);

  bool get isPushing => _isPushing;
  set isPushing(bool v) => _set(() => _isPushing = v);

  InitialSyncProgress? get initialSync => _initialSync;
  set initialSync(InitialSyncProgress? v) => _set(() => _initialSync = v);

  AssetTransferSummary get assets => _assets;
  set assets(AssetTransferSummary v) => _set(() => _assets = v);

  int? get lastSyncedAt => _lastSyncedAt;
  set lastSyncedAt(int? v) => _set(() => _lastSyncedAt = v);

  int? get nextRetryAt => _nextRetryAt;
  set nextRetryAt(int? v) => _set(() => _nextRetryAt = v);

  bool get isOnline => _isOnline;
  set isOnline(bool v) => _set(() => _isOnline = v);

  Duration? get clockSkew => _clockSkew;
  set clockSkew(Duration? v) => _set(() => _clockSkew = v);

  // ---- issues ---------------------------------------------------------------------------

  /// Keys of the active issues.
  Iterable<String> get issueKeys => _issues.keys;

  SyncIssue? issue(String key) => _issues[key];

  /// Adds the issue under [key], or keeps the one already there (message updated, count and
  /// times unchanged) — for conditions that hold for a while (halts, clocks, quarantine).
  void setIssue(
    String key,
    SyncIssueCode code,
    String message, {
    EntityRef? ref,
    AssetId? assetId,
    String? nodeId,
  }) {
    final old = _issues[key];
    if (old != null && old.code == code && old.message == message) return;
    final now = nowMillis();
    _set(
      () => _issues[key] = SyncIssue(
        code: code,
        message: message,
        firstAt: old?.firstAt ?? now,
        lastAt: old?.lastAt ?? now,
        count: old?.count ?? 1,
        ref: ref,
        assetId: assetId,
        nodeId: nodeId,
      ),
    );
  }

  /// One more occurrence under [key]: count + 1 and lastAt = now (firstAt kept), or a new
  /// issue — for events (malformed data, foreign owner, newer format).
  void raiseIssue(
    String key,
    SyncIssueCode code,
    String message, {
    EntityRef? ref,
    AssetId? assetId,
    String? nodeId,
  }) {
    final old = _issues[key];
    final now = nowMillis();
    _set(
      () => _issues[key] = SyncIssue(
        code: code,
        message: message,
        firstAt: old?.firstAt ?? now,
        lastAt: now,
        count: (old?.count ?? 0) + 1,
        ref: ref,
        assetId: assetId,
        nodeId: nodeId,
      ),
    );
  }

  void clearIssue(String key) {
    if (!_issues.containsKey(key)) return;
    _set(() => _issues.remove(key));
  }

  void clearIssues(bool Function(String key, SyncIssue issue) test) {
    final keys = [
      for (final MapEntry(:key, :value) in _issues.entries)
        if (test(key, value)) key,
    ];
    if (keys.isEmpty) return;
    _set(() => keys.forEach(_issues.remove));
  }

  /// Several input changes as one status change.
  void batch(void Function() change) => _set(change);

  int _depth = 0;

  void _set(void Function() change) {
    _depth++;
    try {
      change();
    } finally {
      _depth--;
    }
    if (_depth == 0) _changed();
  }

  // ---- publishing -----------------------------------------------------------------------

  SyncStatus _build() {
    final issues = [
      for (final i in _issues.values)
        if (i.isBlocking) i,
      for (final i in _issues.values)
        if (!i.isBlocking) i,
    ];
    return SyncStatus(
      phase: _phase,
      display: displayOf(
        phase: _phase,
        hasBlockingIssue: issues.isNotEmpty && issues.first.isBlocking,
        quarantinedUploads: _quarantinedUploads,
        pendingUploads: _pendingUploads,
        isPushing: _isPushing,
        assets: _assets,
      ),
      user: _user,
      pendingUploads: _pendingUploads,
      quarantinedUploads: _quarantinedUploads,
      isPushing: _isPushing,
      initialSync: _initialSync,
      assets: _assets,
      lastSyncedAt: _lastSyncedAt,
      nextRetryAt: _nextRetryAt,
      issues: List.unmodifiable(issues),
      isOnline: _isOnline,
      clockSkew: _clockSkew,
    );
  }

  void _changed() {
    if (_closed) return;
    final next = _build();
    if (next == _current) return;
    _current = next;
    if (next.phase != _published.phase || next.display != _published.display) {
      _publish();
    } else if (_cooldown == null) {
      _publish();
    } else {
      _dirty = true;
    }
  }

  void _publish() {
    _dirty = false;
    if (_current == _published) return;
    _published = _current;
    _out.add(_current);
    _cooldown?.cancel();
    _cooldown = Timer(throttle, _cooledDown);
  }

  void _cooledDown() {
    _cooldown = null;
    if (_dirty && !_closed) _publish();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cooldown?.cancel();
    _cooldown = null;
    await _out.close();
  }
}
