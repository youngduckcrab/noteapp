// lib/src/testing/fake_platforms.dart — (v2.1, m5-7/06-pdf 4.3.2 — CP-PDF-6 + PDF review
// M-1) the three platform fakes of package:media_io/testing.dart. VM only (assert !kIsWeb):
// they feed media_io's own service / engine tests (native record engine, just_audio player,
// image_picker); in Chrome the recorder is media_io's MediaRecorder engine, so Chrome tests and
// the app smoke override CORE's audio ports with FakeAudioRecorder / FakeAudioPlayback instead.
//
// Plain `extends` of each platform base class — its constructor passes the platform token, so
// `XPlatform.instance = fake` passes the token check. NO MockPlatformInterfaceMixin: it is
// @visibleForTesting (an analysis error in lib/ — analysis_options
// invalid_use_of_visible_for_testing_member: error). Only the platform interface packages are
// imported here (and testing_vm_factory.dart for the one file write of FakeRecordPlatform).
//
// 2차 foundation step R2-B4 (T30): the basic behaviour below. PDF T31b / T32 / T37 extend the
// scripting when their service tests need more.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import '../testing_vm_factory.dart';

/// The assert message of every VM-only media_io test helper (06-pdf 4.3.2).
const String mediaFakesVmOnlyMessage =
    'media_io platform fakes are VM-only; in Chrome override CORE audio ports with '
    'FakeAudioRecorder / FakeAudioPlayback';

/// record's platform for VM tests of the native engine: scripted permission and encoder support,
/// the state events it emits (record / pause / stop — also unprompted, for interruptions), and the
/// file bytes stop() "finishes". Records every call (create, start(config, path), pause, stop …).
///
/// [calls] entries: `create`, `hasPermission(request: <bool>)`, `isEncoderSupported(<encoder>)`,
/// `start(<encoder>, <bitRate>, <sampleRate>, <numChannels>, <path>)`, `startStream`,
/// `pause`, `resume`, `stop`, `cancel`, `dispose`, `getAmplitude`, `listInputDevices`,
/// `isRecording`, `isPaused`; (T33) while defaultTargetPlatform is iOS, AudioRecorder.ios is a
/// recording fake: `ios.manageAudioSession(<bool>)`, `ios.setAudioSessionActive(<bool>)`,
/// `ios.setAudioSessionCategory(<category>)`.
final class FakeRecordPlatform extends RecordPlatform {
  FakeRecordPlatform({
    this.permission = true,
    Set<AudioEncoder> encoders = const {AudioEncoder.aacLc, AudioEncoder.opus},
  }) : encoders = {...encoders} {
    assert(!kIsWeb, mediaFakesVmOnlyMessage);
  }

  /// RecordPlatform.instance = a new fake.
  static FakeRecordPlatform install({bool permission = true}) {
    final fake = FakeRecordPlatform(permission: permission);
    RecordPlatform.instance = fake;
    return fake;
  }

  /// hasPermission's answer (change it between calls to script a denial).
  bool permission;

  /// isEncoderSupported's answers.
  final Set<AudioEncoder> encoders;

  /// written to the start(path) file at stop()
  Uint8List fileBytes = Uint8List(0);

  /// (T33) The config of the last start / startStream.
  RecordConfig? lastConfig;

  /// (T33) When set, start() reports it through setOnConfigChanged (the device changed the
  /// request — e.g. a lower bit rate).
  RecordConfig? appliedConfig;

  /// (T33) The next start() throws this (once).
  Object? startError;

  final List<String> _calls = [];
  final Map<String, _FakeRecorder> _recorders = {};

  List<String> get calls => List.unmodifiable(_calls);

  /// e.g. a system pause: every recorder takes [state] and emits it on onStateChanged.
  void emitState(RecordState state) {
    for (final recorder in _recorders.values) {
      recorder.state = state;
      recorder.events.add(state);
    }
  }

  _FakeRecorder _recorder(String recorderId) =>
      _recorders[recorderId] ??= _FakeRecorder();

  void _set(String recorderId, RecordState state) {
    final recorder = _recorder(recorderId);
    recorder.state = state;
    recorder.events.add(state);
  }

  @override
  Future<void> create(String recorderId) async {
    _calls.add('create');
    _recorder(recorderId);
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async {
    _calls.add('hasPermission(request: $request)');
    return permission;
  }

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async {
    _calls.add('isEncoderSupported(${encoder.name})');
    return encoders.contains(encoder);
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    _calls.add(
      'start(${config.encoder.name}, ${config.bitRate}, ${config.sampleRate}, '
      '${config.numChannels}, $path)',
    );
    lastConfig = config;
    if (startError case final error?) {
      startError = null;
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    final recorder = _recorder(recorderId)..path = path;
    _set(recorderId, RecordState.record);
    if (appliedConfig case final applied?) {
      recorder.onConfigChanged?.call(applied);
    }
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    _calls.add('startStream');
    lastConfig = config;
    _set(recorderId, RecordState.record);
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<void> pause(String recorderId) async {
    _calls.add('pause');
    _set(recorderId, RecordState.pause);
  }

  @override
  Future<void> resume(String recorderId) async {
    _calls.add('resume');
    _set(recorderId, RecordState.record);
  }

  /// Writes [fileBytes] to the start(path) file and returns that path (null when nothing was
  /// started).
  @override
  Future<String?> stop(String recorderId) async {
    _calls.add('stop');
    final recorder = _recorder(recorderId);
    final path = recorder.path;
    if (path != null) writeMediaTestFile(path, fileBytes);
    recorder.path = null;
    _set(recorderId, RecordState.stop);
    return path;
  }

  @override
  Future<void> cancel(String recorderId) async {
    _calls.add('cancel');
    _recorder(recorderId).path = null;
    _set(recorderId, RecordState.stop);
  }

  @override
  Future<bool> isRecording(String recorderId) async {
    _calls.add('isRecording');
    return _recorder(recorderId).state != RecordState.stop;
  }

  @override
  Future<bool> isPaused(String recorderId) async {
    _calls.add('isPaused');
    return _recorder(recorderId).state == RecordState.pause;
  }

  @override
  Future<void> dispose(String recorderId) async {
    _calls.add('dispose');
    await _recorders.remove(recorderId)?.events.close();
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async {
    _calls.add('getAmplitude');
    return Amplitude(current: -160, max: -160);
  }

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async {
    _calls.add('listInputDevices');
    return const [];
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      _recorder(recorderId).events.stream;

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) => _recorder(recorderId).onConfigChanged = handler;

  @override
  RecordIos? getIos(String recorderId) =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? _FakeRecordIos(_calls)
      : null;
}

/// AudioRecorder.ios while the target platform is iOS: records its calls.
final class _FakeRecordIos implements RecordIos {
  _FakeRecordIos(this._calls);

  final List<String> _calls;

  @override
  Future<void> manageAudioSession(bool manage) async =>
      _calls.add('ios.manageAudioSession($manage)');

  @override
  Future<void> setAudioSessionActive(bool active) async =>
      _calls.add('ios.setAudioSessionActive($active)');

  @override
  Future<void> setAudioSessionCategory({
    IosAudioCategory category = IosAudioCategory.playAndRecord,
    List<IosAudioCategoryOptions> options = const [
      IosAudioCategoryOptions.duckOthers,
      IosAudioCategoryOptions.defaultToSpeaker,
      IosAudioCategoryOptions.allowBluetooth,
      IosAudioCategoryOptions.allowBluetoothA2DP,
    ],
  }) async => _calls.add('ios.setAudioSessionCategory(${category.name})');
}

final class _FakeRecorder {
  // Closed by FakeRecordPlatform.dispose(recorderId).
  // ignore: close_sinks
  final StreamController<RecordState> events =
      StreamController<RecordState>.broadcast();
  RecordState state = RecordState.stop;
  String? path;
  void Function(RecordConfig config)? onConfigChanged;
}

/// just_audio's platform: duration per source (URL / path), a position you set, speed and seek
/// recorded; processing states ready / completed on demand; can fail a load (unsupported format).
///
/// [calls] entries: `init`, `load:<uri>` (a file path arrives as a file: URI), `play`, `pause`,
/// `seek:<ms>`, `speed:<x>`, `volume:<x>`, `dispose`, `disposePlayer`, `disposeAllPlayers`.
final class FakeJustAudioPlatform extends JustAudioPlatform {
  FakeJustAudioPlatform({this.defaultDuration = const Duration(seconds: 2)}) {
    assert(!kIsWeb, mediaFakesVmOnlyMessage);
  }

  /// JustAudioPlatform.instance = a new fake.
  static FakeJustAudioPlatform install() {
    final fake = FakeJustAudioPlatform();
    JustAudioPlatform.instance = fake;
    return fake;
  }

  /// The duration of a source not in [durations].
  final Duration defaultDuration;

  /// Duration per source URI (a file path arrives as a file: URI).
  final Map<String, Duration> durations = {};

  final List<String> _calls = [];
  final Map<String, _FakeAudioPlayer> _players = {};
  bool _failNextLoad = false;

  List<String> get calls => List.unmodifiable(_calls);

  /// Every player's position (emits a playback event).
  void setPosition(Duration position) {
    for (final player in _players.values) {
      player.position = position;
      player.emit();
    }
  }

  /// Every loaded player reaches the end (processing state completed).
  void complete() {
    for (final player in _players.values) {
      if (player.duration case final duration?) player.position = duration;
      player.processing = ProcessingStateMessage.completed;
      player.emit();
    }
  }

  /// The next load fails like an unsupported format (PlatformException 'unsupported').
  void failNextLoad() => _failNextLoad = true;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    _calls.add('init');
    return _players[request.id] = _FakeAudioPlayer(request.id, this);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    _calls.add('disposePlayer');
    await _players.remove(request.id)?.close();
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    _calls.add('disposeAllPlayers');
    for (final player in [..._players.values]) {
      await player.close();
    }
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

/// The URI of a load request: just_audio 0.10 sends every source inside a playlist
/// (ConcatenatingAudioSourceMessage), so the first URI child is the one.
String _uriOf(AudioSourceMessage source) => switch (source) {
  UriAudioSourceMessage(:final uri) => uri,
  ConcatenatingAudioSourceMessage(:final children) when children.isNotEmpty =>
    _uriOf(children.first),
  _ => source.id,
};

final class _FakeAudioPlayer extends AudioPlayerPlatform {
  _FakeAudioPlayer(super.id, this._platform);

  final FakeJustAudioPlatform _platform;
  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();
  ProcessingStateMessage processing = ProcessingStateMessage.idle;
  Duration position = Duration.zero;
  Duration? duration;

  void emit() {
    if (_events.isClosed) return;
    _events.add(
      PlaybackEventMessage(
        processingState: processing,
        updateTime: DateTime.now(),
        updatePosition: position,
        bufferedPosition: duration ?? Duration.zero,
        duration: duration,
        icyMetadata: null,
        currentIndex: duration == null ? null : 0,
        androidAudioSessionId: null,
      ),
    );
  }

  Future<void> close() => _events.close();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final uri = _uriOf(request.audioSourceMessage);
    _platform._calls.add('load:$uri');
    if (_platform._failNextLoad) {
      _platform._failNextLoad = false;
      processing = ProcessingStateMessage.idle;
      throw PlatformException(code: 'unsupported', message: 'unsupported');
    }
    duration = _platform.durations[uri] ?? _platform.defaultDuration;
    position = request.initialPosition ?? Duration.zero;
    processing = ProcessingStateMessage.ready;
    emit();
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _platform._calls.add('play');
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _platform._calls.add('pause');
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    final to = request.position ?? Duration.zero;
    _platform._calls.add('seek:${to.inMilliseconds}');
    position = to;
    // Like the real players: a seek away from the end is ready again.
    if (processing == ProcessingStateMessage.completed) {
      processing = ProcessingStateMessage.ready;
    }
    emit();
    return SeekResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    _platform._calls.add('speed:${request.speed}');
    return SetSpeedResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    _platform._calls.add('volume:${request.volume}');
    return SetVolumeResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async => SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
    SetShuffleOrderRequest request,
  ) async => SetShuffleOrderResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
  setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
  setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request,
  ) async => SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
    SetPreferredPeakBitRateRequest request,
  ) async => SetPreferredPeakBitRateResponse();

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
    SetAllowsExternalPlaybackRequest request,
  ) async => SetAllowsExternalPlaybackResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async => SetAndroidAudioAttributesResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _platform._calls.add('dispose');
    await close();
    return DisposeResponse();
  }
}

/// (CP-PDF-6) image_picker's platform: a queue of picks (bytes + name) or null (= cancel).
///
/// getImageFromSource takes the next queued pick (an empty queue = cancel) and records the
/// source in [sources].
final class FakeImagePickerPlatform extends ImagePickerPlatform {
  FakeImagePickerPlatform() {
    assert(!kIsWeb, mediaFakesVmOnlyMessage);
  }

  final List<({Uint8List bytes, String name})?> _queue = [];

  /// The source of every pick asked for, in order.
  final List<ImageSource> sources = [];

  /// The answer of a later pick: [bytes] named [name], or null (the user cancelled).
  void enqueue(Uint8List? bytes, {String name = 'photo.jpg'}) =>
      _queue.add(bytes == null ? null : (bytes: bytes, name: name));

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    sources.add(source);
    if (_queue.isEmpty) return null;
    final pick = _queue.removeAt(0);
    if (pick == null) return null;
    // On the VM an XFile's name is the last segment of its path (cross_file ignores `name`).
    return XFile.fromData(
      pick.bytes,
      name: pick.name,
      path: pick.name,
      length: pick.bytes.length,
    );
  }
}
