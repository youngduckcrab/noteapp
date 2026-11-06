// lib/src/playback/playback_service.dart — JustAudioPlaybackService implements
// core.AudioPlaybackService (m5-7/06-pdf 4.2.3, 6.11). Internal: mediaIoOverrides() (PDF T37)
// builds it with the CORE stores read on first use (4.2.2).
//
// open: close what is open → loading → (web, P-B) the stop path's hand-off Blob, else the asset
// row (iOS native + webm/opus → failed + unsupportedFormat without opening — 6.11.4) → the bytes
// (missing → RemoteAssetFetcher.ensureLocal → again — 1차 P-2; still missing → failed
// assetMissing) → the platform source (web Blob URL with preload: false, native play cache file
// — 6.11.3) → load → speed = media.playbackSpeed → ready. The web length is Recording.durationMs
// (S-7); native takes the player's length when it has one. A player format error → failed +
// unsupportedFormat. The player's states map to phases by 6.11.2. play() does nothing while
// the recorder is active (contract 7.2.4 v2.1, CP-PDF-10). positionMs() reads the player's Dart
// extrapolation (no platform call — every frame is fine, 6.11.5).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import '../providers.dart';
import 'audio_source.dart';
import 'audio_source_factory.dart';
import 'handoff_blob.dart';
import 'player_port.dart';

final class JustAudioPlaybackService implements core.AudioPlaybackService {
  JustAudioPlaybackService({
    required this._assets,
    required this._settings,
    this._fetcher,
    bool Function()? recorderActive,
    PlayerPort Function()? player,
    AudioSourceProvider? sources,
    this._handoff,
  }) : _recorderActive = recorderActive ?? _never,
       _newPlayer = player ?? JustAudioPlayerPort.new,
       _sources = sources ?? createPlatformAudioSources();

  static bool _never() => false;

  final core.AssetStore Function() _assets;
  final core.SettingsRepository Function() _settings;
  final core.RemoteAssetFetcher? Function()? _fetcher;
  final bool Function() _recorderActive;
  final PlayerPort Function() _newPlayer;
  final AudioSourceProvider _sources;
  final PlaybackHandoff? _handoff;

  core.PlaybackStatus _status = const core.PlaybackStatus();
  final StreamController<core.PlaybackStatus> _ctrl =
      StreamController<core.PlaybackStatus>.broadcast(sync: true);
  PlayerPort? _port;
  StreamSubscription<PlayerSnapshot>? _sub;

  /// Bumped by every open / close / dispose: work of an older open stops at its next step.
  int _gen = 0;

  /// play() was asked since the open (a pause then reads 'paused', not 'ready' — 6.11.2).
  bool _played = false;

  /// The source was opened with preload: false and has not loaded yet (web — S-7).
  bool _deferred = false;

  /// (web) A seekMs before the first play of a deferred source: applied by that play (4.2.3).
  int? _pendingSeekMs;
  bool _disposed = false;

  @override
  core.PlaybackStatus get status => _status;

  @override
  Stream<core.PlaybackStatus> get statusStream => Stream.multi((c) {
    c.add(_status);
    final sub = _ctrl.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  void _emit(core.PlaybackStatus next) {
    if (next == _status || _disposed) return;
    _status = next;
    _ctrl.add(next);
  }

  bool get _isOpen => switch (_status.phase) {
    core.PlaybackPhase.ready ||
    core.PlaybackPhase.playing ||
    core.PlaybackPhase.paused ||
    core.PlaybackPhase.completed => true,
    _ => false,
  };

  PlayerPort get _player {
    if (_port case final p?) return p;
    final p = _port = _newPlayer();
    _sub = p.snapshots.listen(_onSnapshot, onError: _onPlayerError);
    return p;
  }

  // 6.11.2: player state → phase, once open() has made the recording ready.
  void _onSnapshot(PlayerSnapshot s) {
    if (!_isOpen) return;
    final core.PlaybackPhase next;
    if (s.processing == PlayerProcessing.completed) {
      next = core.PlaybackPhase.completed;
      // just_audio stays 'playing' at the end; pausing keeps a later seek from playing again.
      if (s.playing) unawaited(_player.pause().catchError((Object _) {}));
    } else if (s.playing && s.processing != PlayerProcessing.idle) {
      next = core.PlaybackPhase.playing;
      _played = true;
      _deferred = false;
    } else if (!s.playing && s.processing == PlayerProcessing.ready) {
      next = _played ? core.PlaybackPhase.paused : core.PlaybackPhase.ready;
    } else {
      return;
    }
    _emit(_status.copyWith(phase: next));
  }

  void _onPlayerError(Object error) {
    if (!_isOpen) return; // open() reports its own load errors
    final format = error is PlayerFailure && error.formatError;
    _emit(
      _status.copyWith(
        phase: core.PlaybackPhase.failed,
        unsupportedFormat: format,
        error: MediaIoException(
          format
              ? MediaErrorCode.unsupportedFormat
              : MediaErrorCode.playbackFailed,
          detail: 'player error while open',
          cause: error is PlayerFailure ? error.cause : error,
        ),
      ),
    );
  }

  void _fail(
    int gen,
    MediaIoException error, {
    bool unsupportedFormat = false,
  }) {
    if (gen != _gen) return;
    _emit(
      _status.copyWith(
        phase: core.PlaybackPhase.failed,
        unsupportedFormat: unsupportedFormat,
        error: error,
      ),
    );
  }

  /// iOS native: AVPlayer does not open WebM / Opus (6.11.4).
  static bool _unplayableHere(String mimeType) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    final m = mimeType.toLowerCase();
    return m.contains('webm') || m.contains('opus');
  }

  @override
  Future<void> open(core.Recording recording) async {
    if (_disposed) throw StateError('JustAudioPlaybackService was disposed');
    final gen = ++_gen;
    await _unloadPlayer();
    if (gen != _gen) return;
    _played = false;
    _deferred = false;
    _pendingSeekMs = null;
    _emit(
      core.PlaybackStatus(
        phase: core.PlaybackPhase.loading,
        recordingId: recording.id,
        durationMs: math.max(0, recording.durationMs),
        speed: _status.speed,
      ),
    );
    try {
      final speed = await _rememberedSpeed();
      if (gen != _gen) return;
      _emit(_status.copyWith(speed: speed));
      final handoff = _handoff?.take(recording.assetId);
      String? mimeType;
      String? fileName;
      if (handoff == null) {
        final asset = await _assets().getAsset(recording.assetId);
        if (gen != _gen) return;
        if (asset == null) {
          return _fail(
            gen,
            const MediaIoException(
              MediaErrorCode.assetMissing,
              detail: 'no asset row',
            ),
          );
        }
        if (_unplayableHere(asset.mimeType)) {
          return _fail(
            gen,
            const MediaIoException(
              MediaErrorCode.unsupportedFormat,
              detail: 'webm / opus on iOS',
            ),
            unsupportedFormat: true,
          );
        }
        mimeType = asset.mimeType;
        fileName = asset.fileName;
      }
      final source = await _sources.prepare(
        recording.assetId,
        mimeType: mimeType,
        fileName: fileName,
        bytes: () => _bytesOf(recording.assetId),
        handoff: handoff,
      );
      if (gen != _gen) return;
      if (source == null) {
        return _fail(
          gen,
          const MediaIoException(
            MediaErrorCode.assetMissing,
            detail: 'no bytes on this device',
          ),
        );
      }
      final read = await _player.load(source);
      if (gen != _gen) return;
      _deferred = source is PlayerUrlSource && !source.preload;
      await _player.setSpeed(speed);
      if (gen != _gen) return;
      final readMs = read?.inMilliseconds;
      final durationMs =
          _sources.usesRecordingDuration || readMs == null || readMs <= 0
          ? recording.durationMs
          : readMs;
      _emit(
        _status.copyWith(
          phase: core.PlaybackPhase.ready,
          durationMs: math.max(0, durationMs),
        ),
      );
    } on PlayerFailure catch (e) {
      _fail(
        gen,
        MediaIoException(
          e.formatError
              ? MediaErrorCode.unsupportedFormat
              : MediaErrorCode.playbackFailed,
          detail: 'load failed',
          cause: e.cause,
        ),
        unsupportedFormat: e.formatError,
      );
    } on Object catch (e) {
      _fail(
        gen,
        MediaIoException(
          MediaErrorCode.playbackFailed,
          detail: 'open failed',
          cause: e,
        ),
      );
    }
  }

  /// The local bytes; when missing and a fetcher is set, ensureLocal and read again (1차 P-2).
  Future<Uint8List?> _bytesOf(core.AssetId id) async {
    final assets = _assets();
    final local = await assets.readBytes(id);
    if (local != null) return local;
    final fetcher = _fetcher?.call();
    if (fetcher == null) return null;
    if (!await fetcher.ensureLocal(id)) return null;
    return assets.readBytes(id);
  }

  Future<double> _rememberedSpeed() async {
    try {
      final v = await _settings().get(MediaSettingKeys.playbackSpeed);
      return v.isFinite ? v.clamp(0.5, 2.0) : 1.0;
    } on Object {
      return 1.0;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed || _recorderActive()) return;
    final phase = _status.phase;
    if (phase != core.PlaybackPhase.ready &&
        phase != core.PlaybackPhase.paused &&
        phase != core.PlaybackPhase.completed) {
      return;
    }
    final gen = _gen;
    final player = _player;
    if (phase == core.PlaybackPhase.completed) {
      await player.seek(Duration.zero);
    } else if (_pendingSeekMs case final ms?) {
      await player.seek(Duration(milliseconds: ms));
    }
    if (gen != _gen) return;
    _pendingSeekMs = null;
    _played = true;
    await player.play();
  }

  @override
  Future<void> pause() async {
    if (!_isOpen) return;
    await _player.pause();
  }

  @override
  Future<void> seekMs(int positionMs) async {
    if (!_isOpen) return;
    final ms = positionMs.clamp(0, _status.durationMs);
    if (_deferred) {
      _pendingSeekMs = ms;
      return;
    }
    await _player.seek(Duration(milliseconds: ms));
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (!_isOpen) return;
    final v = speed.isFinite ? speed.clamp(0.5, 2.0) : 1.0;
    await _player.setSpeed(v);
    _emit(_status.copyWith(speed: v));
    unawaited(
      Future(() => _settings().set(MediaSettingKeys.playbackSpeed, v))
          .catchError((Object _) {}),
    );
  }

  @override
  int positionMs() {
    final duration = _status.durationMs;
    switch (_status.phase) {
      case core.PlaybackPhase.completed:
        return duration;
      case core.PlaybackPhase.ready ||
          core.PlaybackPhase.playing ||
          core.PlaybackPhase.paused:
        if (_pendingSeekMs case final ms?) return ms;
        if (_deferred) return 0;
        final p = _port?.position.inMilliseconds ?? 0;
        return p.clamp(0, duration);
      case core.PlaybackPhase.idle ||
          core.PlaybackPhase.loading ||
          core.PlaybackPhase.failed:
        return 0;
    }
  }

  @override
  Future<void> close() async {
    if (_disposed) return;
    _gen++;
    await _unloadPlayer();
    _played = false;
    _deferred = false;
    _pendingSeekMs = null;
    _emit(const core.PlaybackStatus());
  }

  Future<void> _unloadPlayer() async {
    try {
      await _port?.unload();
    } on Object {
      // A player that cannot stop is replaced by the next load anyway.
    }
    _sources.release();
  }

  /// Provider clean-up (PDF T37): stops, frees the source and the player. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _gen++;
    _emit(const core.PlaybackStatus());
    _disposed = true;
    unawaited(_sub?.cancel());
    _sub = null;
    final port = _port;
    _port = null;
    _sources.release();
    _handoff?.clear();
    unawaited(_ctrl.close());
    try {
      await port?.dispose();
    } on Object {
      // Nothing more to free.
    }
  }
}
