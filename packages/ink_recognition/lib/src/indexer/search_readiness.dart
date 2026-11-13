// lib/src/indexer/search_readiness.dart — (handwriting search, m5-7/05-library
// 6.19a) whether handwriting can be found by the library search yet, and the
// actions that make it so. The app shell adapts it to feature_library's
// LibraryInkSearch slot (feature packages never import ink_recognition).
//
// Phase, first match wins:
//   recog.autoIndex off                       → autoIndexOff
//   the engine or the model is unsupported (RecognizerUnsupported from the
//     indexer or modelState, modelState unsupported)
//                                             → unsupported
//   ModelDownloads of the language: waiting for Wi-Fi / running
//                                             → waitingForWifi / modelDownloading
//   ModelDownloads failed, unless the indexer asks again (its waitingModel
//     reads 'waiting for Wi-Fi' / 'downloading') → modelFailed
//   indexer waitingModel: 'waiting for Wi-Fi' / 'downloading' /
//     'download failed' / 'not downloaded' / 'unsupported'
//                                             → waitingForWifi / modelDownloading /
//                                               modelFailed / modelMissing / unsupported
//   indexer recognizing / waitingInput        → indexing (remainingPages = queue, + 1 in flight)
//   indexer idle / waitingInput(0) while its catch-up still looks for stale
//     pages                                   → indexing (remainingPages 0: still counting)
//   indexer off (not started yet): modelState notDownloaded / downloading
//                                             → modelMissing / modelDownloading, else unavailable
//   otherwise                                 → ready
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/report_error.dart';
import '../model/candidates.dart';
import '../model/failures.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/model_admin.dart';
import '../providers.dart';
import '../settings/recognition_settings_keys.dart';
import '../settings/recognition_settings_section.dart' show onAutoIndexTurnedOn;
import '../ui/model_downloads.dart';
import 'handwriting_indexer.dart';
import 'indexer_status.dart';

/// Why handwriting is (not yet) found by the library search.
enum HandwritingSearchPhase {
  /// Nothing to say: no engine on this device, or not started yet.
  unavailable,

  /// Handwriting is indexed (or the indexer is caught up).
  ready,

  /// '검색용 자동 인식' is off.
  autoIndexOff,

  /// The model of the language is missing and no download runs.
  modelMissing,

  /// The model is being downloaded.
  modelDownloading,

  /// Android: a Wi-Fi-only download waits for Wi-Fi.
  waitingForWifi,

  /// The last download failed.
  modelFailed,

  /// Pages are waiting to be recognized ([HandwritingSearchStatus.remainingPages];
  /// 0 while the catch-up is still counting them).
  indexing,

  /// The engine or the model of the language is not supported on this device:
  /// handwriting is never found (said once, nothing to do).
  unsupported,
}

@immutable
final class HandwritingSearchStatus {
  const HandwritingSearchStatus({
    this.phase = HandwritingSearchPhase.unavailable,
    this.remainingPages = 0,
    this.confirmCellularFirst = false,
  });

  final HandwritingSearchPhase phase;

  /// [HandwritingSearchPhase.indexing]: pages still to recognize.
  final int remainingPages;

  /// iPad with recog.modelWifiOnly: a download may use cellular data at
  /// once (iOS does not wait for Wi-Fi), so the UI confirms first (6.7.4).
  final bool confirmCellularFirst;

  @override
  bool operator ==(Object other) =>
      other is HandwritingSearchStatus &&
      other.phase == phase &&
      other.remainingPages == remainingPages &&
      other.confirmCellularFirst == confirmCellularFirst;

  @override
  int get hashCode => Object.hash(phase, remainingPages, confirmCellularFirst);

  @override
  String toString() =>
      'HandwritingSearchStatus(${phase.name}, remaining $remainingPages'
      '${confirmCellularFirst ? ', confirm cellular' : ''})';
}

final class HandwritingSearchReadiness {
  HandwritingSearchReadiness._(
    this._settings,
    this._recognizer,
    this._downloads,
    this._indexer,
  );

  final core.SettingsRepository _settings;
  final HandwritingRecognizer _recognizer;
  final ModelDownloads _downloads;
  final HandwritingIndexer _indexer;

  final ValueNotifier<HandwritingSearchStatus> _status = ValueNotifier(
    const HandwritingSearchStatus(),
  );
  final List<StreamSubscription<Object?>> _subscriptions = [];
  bool _disposed = false;

  bool? _autoIndex;
  String _lang = 'ko';
  bool _wifiOnly = true;
  RecognitionModelState? _model;
  bool _modelUnsupported = false;
  int _modelAsk = 0;

  ValueListenable<HandwritingSearchStatus> get status => _status;

  void _start() {
    _indexer.status.addListener(_update);
    catchUpRunningOf(_indexer).addListener(_update);
    _downloads.addListener(_onDownloads);
    _subscriptions
      ..add(
        _settings
            .watch(RecognitionSettingsKeys.autoIndex)
            .listen((v) => _set(() => _autoIndex = v), onError: _onError),
      )
      ..add(
        _settings.watch(RecognitionSettingsKeys.language).listen((v) {
          _lang = recognitionLanguageOf(v);
          unawaited(_askModel());
        }, onError: _onError),
      )
      ..add(
        _settings
            .watch(RecognitionSettingsKeys.modelWifiOnly)
            .listen((v) => _set(() => _wifiOnly = v), onError: _onError),
      );
    if (_recognizer case final RecognizerModelAdmin admin) {
      _subscriptions.add(
        admin.modelChanges.listen((tag) {
          if (tag == _lang) unawaited(_askModel());
        }, onError: _onError),
      );
    }
    unawaited(_askModel());
  }

  void _onError(Object e, StackTrace s) =>
      reportRecognitionError(e, s, 'handwriting search status input');

  void _set(void Function() change) {
    if (_disposed) return;
    change();
    _update();
  }

  void _onDownloads() {
    unawaited(_askModel());
    _update();
  }

  Future<void> _askModel() async {
    final ask = ++_modelAsk;
    RecognitionModelState? state;
    var unsupported = false;
    try {
      state = await _recognizer.modelState(_lang);
    } on RecognizerUnsupported {
      state = null;
      unsupported = true;
    } on Object {
      state = null;
    }
    if (_disposed || ask != _modelAsk) return;
    _model = state;
    _modelUnsupported =
        unsupported || state == RecognitionModelState.unsupported;
    _update();
  }

  void _update() {
    if (_disposed) return;
    _status.value = _compute();
  }

  bool get _confirmCellularFirst => switch (_recognizer) {
    RecognizerModelAdmin(enforcesWifiOnly: false) => _wifiOnly,
    _ => false,
  };

  HandwritingSearchStatus _compute() {
    HandwritingSearchStatus of(HandwritingSearchPhase p, [int remaining = 0]) =>
        HandwritingSearchStatus(
          phase: p,
          remainingPages: remaining,
          confirmCellularFirst: _confirmCellularFirst,
        );
    final auto = _autoIndex;
    if (auto == null) return of(HandwritingSearchPhase.unavailable);
    if (!auto) return of(HandwritingSearchPhase.autoIndexOff);
    if (_modelUnsupported || isUnsupportedOn(_indexer)) {
      return of(HandwritingSearchPhase.unsupported);
    }
    final s = _indexer.status.value;
    final why = s.phase == HandwritingIndexerPhase.waitingModel
        ? s.lastError ?? ''
        : '';
    final indexerAsks =
        why.endsWith('waiting for Wi-Fi') || why.endsWith('downloading');
    switch (_downloads.stateOf(_lang)) {
      case ModelDownloadState.waitingForWifi:
        return of(HandwritingSearchPhase.waitingForWifi);
      case ModelDownloadState.downloading:
        return of(HandwritingSearchPhase.modelDownloading);
      case ModelDownloadState.failed:
        // A retry of the indexer (the search opened) runs: its state, not
        // the old failure.
        if (_model != RecognitionModelState.ready && !indexerAsks) {
          return of(HandwritingSearchPhase.modelFailed);
        }
      case ModelDownloadState.none:
    }
    switch (s.phase) {
      case HandwritingIndexerPhase.disabled:
        return of(HandwritingSearchPhase.autoIndexOff);
      case HandwritingIndexerPhase.waitingModel:
        if (why.endsWith('waiting for Wi-Fi')) {
          return of(HandwritingSearchPhase.waitingForWifi);
        }
        if (why.endsWith('downloading')) {
          return of(HandwritingSearchPhase.modelDownloading);
        }
        if (why.endsWith('download failed')) {
          return of(HandwritingSearchPhase.modelFailed);
        }
        if (why.endsWith('unsupported')) {
          return of(HandwritingSearchPhase.unsupported);
        }
        return of(HandwritingSearchPhase.modelMissing);
      case HandwritingIndexerPhase.recognizing:
        return of(HandwritingSearchPhase.indexing, s.queuedPages + 1);
      case HandwritingIndexerPhase.waitingInput:
        if (s.queuedPages > 0) {
          return of(HandwritingSearchPhase.indexing, s.queuedPages);
        }
        return catchUpRunningOf(_indexer).value
            ? of(HandwritingSearchPhase.indexing)
            : of(HandwritingSearchPhase.ready);
      case HandwritingIndexerPhase.off:
        return switch (_model) {
          RecognitionModelState.notDownloaded => of(
            HandwritingSearchPhase.modelMissing,
          ),
          RecognitionModelState.downloading => of(
            HandwritingSearchPhase.modelDownloading,
          ),
          _ => of(HandwritingSearchPhase.unavailable),
        };
      case HandwritingIndexerPhase.idle:
        return catchUpRunningOf(_indexer).value
            ? of(HandwritingSearchPhase.indexing)
            : of(HandwritingSearchPhase.ready);
      case HandwritingIndexerPhase.paused:
        return of(HandwritingSearchPhase.ready);
    }
  }

  /// [켜기]: recog.autoIndex on, and the model asked for as the settings
  /// switch does (onAutoIndexTurnedOn).
  Future<void> turnOnAutoIndex() async {
    if (_disposed) return;
    try {
      await _settings.set(RecognitionSettingsKeys.autoIndex, true);
    } on Object catch (e, s) {
      reportRecognitionError(e, s, 'saving recog.autoIndex');
      return;
    }
    await onAutoIndexTurnedOn(
      recognizer: _recognizer,
      downloads: _downloads,
      language: _lang,
      wifiOnly: _wifiOnly,
    );
  }

  /// [지금 받기]: the model of the language (recog.modelWifiOnly), or with
  /// [cellular] at once over cellular data (after the UI confirmed it).
  /// Completes when the download ends (never with an error).
  Future<void> downloadModel({bool cellular = false}) {
    if (_disposed) return Future<void>.value();
    return cellular
        ? _downloads.startCellular(_lang)
        : _downloads.start(_lang, wifiOnly: _wifiOnly);
  }

  /// The library search field got focus or a query was applied: pages
  /// waiting for their quiet time are recognized now (indexDirtyPagesNow; a
  /// failed download is asked again at most once per kModelRetryGap).
  void searchOpened() {
    if (_disposed) return;
    indexDirtyPagesNow(_indexer);
  }

  void _dispose() {
    _disposed = true;
    _modelAsk++;
    _indexer.status.removeListener(_update);
    catchUpRunningOf(_indexer).removeListener(_update);
    _downloads.removeListener(_onDownloads);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    _status.dispose();
  }
}

/// (handwriting search) null without an indexer (the web, no engine).
final handwritingSearchReadinessProvider =
    Provider<HandwritingSearchReadiness?>((ref) {
      final indexer = ref.watch(handwritingIndexerProvider);
      if (indexer == null) return null;
      final readiness = HandwritingSearchReadiness._(
        ref.watch(core.settingsRepositoryProvider),
        ref.watch(handwritingRecognizerProvider),
        ref.watch(modelDownloadsProvider),
        indexer,
      ).._start();
      ref.onDispose(readiness._dispose);
      return readiness;
    }, name: 'handwritingSearchReadinessProvider');
