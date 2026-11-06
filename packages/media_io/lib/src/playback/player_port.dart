// lib/src/playback/player_port.dart — the player the playback service drives (m5-7/06-pdf
// 6.11.1, 6.11.2): just_audio's AudioPlayer in the app (JustAudioPlayerPort), a scripted player
// in tests (test/support/fake_engines.dart — fake time). Internal, web-safe.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

/// The player's processing state (just_audio's ProcessingState).
enum PlayerProcessing { idle, loading, buffering, ready, completed }

/// What the player is doing: its processing state and whether it was asked to play.
@immutable
final class PlayerSnapshot {
  const PlayerSnapshot(this.processing, {required this.playing});

  static const PlayerSnapshot idle = PlayerSnapshot(
    PlayerProcessing.idle,
    playing: false,
  );

  final PlayerProcessing processing;
  final bool playing;

  @override
  bool operator ==(Object other) =>
      other is PlayerSnapshot &&
      other.processing == processing &&
      other.playing == playing;

  @override
  int get hashCode => Object.hash(processing, playing);

  @override
  String toString() => 'PlayerSnapshot(${processing.name}, playing: $playing)';
}

/// What the player opens (6.11.3).
sealed class PlayerSource {
  const PlayerSource();
}

/// A URL — on the web an object URL of the recording's Blob, opened with preload: false (S-7:
/// the length comes from Recording.durationMs, the bytes load on the first play).
final class PlayerUrlSource extends PlayerSource {
  const PlayerUrlSource(this.url, {this.preload = true});
  final String url;
  final bool preload;

  @override
  String toString() => 'PlayerUrlSource(preload: $preload)';
}

/// A file — native: the play cache file of the asset.
final class PlayerFileSource extends PlayerSource {
  const PlayerFileSource(this.path);
  final String path;

  @override
  String toString() => 'PlayerFileSource';
}

/// The player could not load or play a source. [formatError]: the format does not play here
/// (6.11.4 — the status gets unsupportedFormat).
final class PlayerFailure implements Exception {
  const PlayerFailure({required this.formatError, this.cause});
  final bool formatError;
  final Object? cause;

  @override
  String toString() =>
      'PlayerFailure(${formatError ? 'format' : 'player'}'
      '${cause == null ? '' : ', cause: ${cause.runtimeType}'})';
}

abstract interface class PlayerPort {
  PlayerSnapshot get snapshot;

  /// Every change of [snapshot] (distinct), in order; a player error arrives as a
  /// [PlayerFailure] stream error. Broadcast.
  Stream<PlayerSnapshot> get snapshots;

  /// Opens [source]; the length the player read (null with preload: false or when unknown).
  /// Throws [PlayerFailure].
  Future<Duration?> load(PlayerSource source);

  /// Asks the player to play. Completes once asked — not at the end of the playback (just_audio's
  /// own play() completes only when the playback pauses or stops).
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);

  /// The player's position, extrapolated in Dart while playing (no platform call — 6.11.5).
  Duration get position;

  /// Stops and forgets the source; the player stays for the next [load].
  Future<void> unload();

  /// Idempotent.
  Future<void> dispose();
}

/// (6.11.2) Whether a just_audio player error means 'this format does not play here': the web's
/// MediaError MEDIA_ERR_DECODE (3) / MEDIA_ERR_SRC_NOT_SUPPORTED (4), Android's
/// ExoPlaybackException.TYPE_SOURCE (0), the AVFoundation 'not recognised / failed to parse /
/// decode failed' codes, or a message that says so (the VM fake: 'unsupported').
bool isPlayerFormatError({
  required int code,
  String? message,
  required bool web,
  required TargetPlatform platform,
}) {
  final m = message?.toLowerCase() ?? '';
  if (m.contains('unsupported') ||
      m.contains('not supported') ||
      m.contains('format') ||
      m.contains('unrecognized') ||
      m.contains('unrecognised')) {
    return true;
  }
  if (web) return code == 3 || code == 4;
  return switch (platform) {
    TargetPlatform.android => code == 0,
    TargetPlatform.iOS || TargetPlatform.macOS => const {
      -11828, // AVErrorFileFormatNotRecognized
      -11829, // AVErrorFileFailedToParse
      -11821, // AVErrorDecodeFailed
    }.contains(code),
    _ => false,
  };
}

PlayerFailure _failureOf(Object error) => switch (error) {
  PlayerFailure() => error,
  ja.PlayerException(:final code, :final message) => PlayerFailure(
    formatError: isPlayerFormatError(
      code: code,
      message: message,
      web: kIsWeb,
      platform: defaultTargetPlatform,
    ),
    cause: error,
  ),
  _ => PlayerFailure(formatError: false, cause: error),
};

/// just_audio's AudioPlayer, made on the first [load] (6.11.1 — handleInterruptions and
/// handleAudioSessionActivation are just_audio's defaults). (P-B) [beforeFirstLoad] runs once
/// before the first load — native wiring passes the speech session configuration of
/// record/audio_session_native.dart (package:audio_session stays in *_native.dart — 3.5 I-3);
/// a failure there is ignored (the platform's default session plays).
final class JustAudioPlayerPort implements PlayerPort {
  JustAudioPlayerPort({
    ja.AudioPlayer Function()? create,
    this._beforeFirstLoad,
  }) : _create = create ?? ja.AudioPlayer.new;

  final ja.AudioPlayer Function() _create;
  final Future<void> Function()? _beforeFirstLoad;
  ja.AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _subs = [];
  final StreamController<PlayerSnapshot> _ctrl =
      StreamController<PlayerSnapshot>.broadcast(sync: true);
  PlayerSnapshot _snapshot = PlayerSnapshot.idle;
  bool _sessionConfigured = false;
  bool _disposed = false;

  /// (PDF T39) A URL source set with preload: false and not loaded yet. just_audio 0.10.6 on the
  /// web never loads such a source on play() (it stays idle with playing = true — V8 found it)
  /// and a seek before the load is lost when the load starts at 0, so the first play() / seek()
  /// loads it first (load() → then the seek / the play request).
  bool _loadPending = false;

  @override
  PlayerSnapshot get snapshot => _snapshot;

  @override
  Stream<PlayerSnapshot> get snapshots => _ctrl.stream;

  ja.AudioPlayer get _p {
    if (_player case final p?) return p;
    final p = _player = _create();
    _subs
      ..add(
        p.playerStateStream.listen(
          (s) => _push(
            PlayerSnapshot(
              _processingOf(s.processingState),
              playing: s.playing,
            ),
          ),
          onError: (Object e) {
            if (!_ctrl.isClosed) _ctrl.addError(_failureOf(e));
          },
        ),
      )
      ..add(
        p.errorStream.listen((e) {
          if (!_ctrl.isClosed) _ctrl.addError(_failureOf(e));
        }),
      );
    return p;
  }

  void _push(PlayerSnapshot next) {
    if (next == _snapshot) return;
    _snapshot = next;
    if (!_ctrl.isClosed) _ctrl.add(next);
  }

  static PlayerProcessing _processingOf(ja.ProcessingState s) => switch (s) {
    ja.ProcessingState.idle => PlayerProcessing.idle,
    ja.ProcessingState.loading => PlayerProcessing.loading,
    ja.ProcessingState.buffering => PlayerProcessing.buffering,
    ja.ProcessingState.ready => PlayerProcessing.ready,
    ja.ProcessingState.completed => PlayerProcessing.completed,
  };

  Future<void> _configureSession() async {
    final configure = _beforeFirstLoad;
    if (_sessionConfigured || configure == null) return;
    _sessionConfigured = true;
    try {
      await configure();
    } on Object {
      // P-B: without it the platform's default session plays (6.11.1).
    }
  }

  @override
  Future<Duration?> load(PlayerSource source) async {
    if (_disposed) throw StateError('JustAudioPlayerPort was disposed');
    await _configureSession();
    _loadPending = false;
    try {
      final length = await switch (source) {
        PlayerUrlSource(:final url, :final preload) => _p.setUrl(
          url,
          preload: preload,
        ),
        PlayerFileSource(:final path) => _p.setFilePath(path),
      };
      _loadPending = source is PlayerUrlSource && !source.preload;
      return length;
    } on Object catch (e) {
      throw _failureOf(e);
    }
  }

  /// Loads a preload: false source before its first play / seek; a failure goes to [snapshots]
  /// as a [PlayerFailure] (false = not loaded).
  Future<bool> _loadIfPending() async {
    if (!_loadPending) return true;
    _loadPending = false;
    try {
      await _p.load();
      return true;
    } on Object catch (e) {
      if (!_ctrl.isClosed) _ctrl.addError(_failureOf(e));
      return false;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    if (!await _loadIfPending() || _disposed) return;
    final p = _p;
    // just_audio's play() completes when the playback pauses or stops; its errors also arrive
    // on errorStream / the state stream.
    unawaited(
      p.play().catchError((Object e) {
        if (!_ctrl.isClosed) _ctrl.addError(_failureOf(e));
      }),
    );
  }

  @override
  Future<void> pause() async {
    if (_disposed || _player == null) return;
    await _p.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed || _player == null) return;
    if (!await _loadIfPending() || _disposed) return;
    await _p.seek(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_disposed) return;
    await _p.setSpeed(speed);
  }

  @override
  Duration get position => _player?.position ?? Duration.zero;

  @override
  Future<void> unload() async {
    _loadPending = false;
    if (_disposed || _player == null) return;
    await _p.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    final p = _player;
    _player = null;
    unawaited(_ctrl.close());
    await p?.dispose();
  }
}
