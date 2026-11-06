// lib/src/ui/model_downloads.dart — (internal) m5-7/05-library 6.7.4, 6.18,
// 6.22: the model downloads the USER starts — a model row's [받기] (the
// settings section; the lab's rows, 6.20; the conversion sheet's model card,
// 6.13) and the '검색용 자동 인식' switch on Android. One entry per language
// while ensureModel runs, shared by every row of the container, so a row
// opened later shows the download that is already running.
//
// - start(tag, wifiOnly:) joins a running download of the tag. On Android
//   (an engine that enforces wifiOnly — RecognizerModelAdmin.enforcesWifiOnly,
//   or an engine without model admin) a wifiOnly download that has not ended
//   after 5 s shows as 'waiting for Wi-Fi' (review S-9).
// - startCellular(tag): [지금 셀룰러로 받기] after its confirmation —
//   ensureModel(tag, wifiOnly: false) beside the waiting one; the first to
//   finish ends the entry (the adapter does not join requests whose wifiOnly
//   differs — 6.7.4).
// - A failed download is reported once (6.22) and the row shows
//   '받지 못했어요 [다시]' until the next start. RecognizerUnsupported is not
//   reported (no engine — nothing to fix).
// - highlight(tag): iOS — turning automatic indexing on emphasises the
//   tag's [받기] (6.18) until a download of it starts.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/report_error.dart';
import '../model/failures.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/model_admin.dart';
import '../providers.dart';

/// How long a user's Wi-Fi-only download may run before the row offers
/// [지금 셀룰러로 받기] (6.7.4 — Android).
const Duration kWifiWaitBeforeCellular = Duration(seconds: 5);

/// What [ModelDownloads] knows about one language.
enum ModelDownloadState {
  /// No download started here (the row shows the engine's modelState).
  none,

  /// ensureModel runs (Wi-Fi only for less than 5 s, or unconditioned).
  downloading,

  /// Android: a Wi-Fi-only download still runs after 5 s.
  waitingForWifi,

  /// The last download failed ('받지 못했어요 [다시]').
  failed,
}

final class _Download {
  final Completer<void> done = Completer<void>();
  int running = 0;
  bool cellular = false;
  bool waitingForWifi = false;
  Timer? wifiTimer;
}

final class ModelDownloads extends ChangeNotifier {
  ModelDownloads(this._recognizer);

  final HandwritingRecognizer _recognizer;
  final Map<String, _Download> _active = {};
  final Set<String> _failed = {};
  final Set<String> _highlighted = {};
  bool _disposed = false;

  /// The engine waits for Wi-Fi when asked (Android); iOS ignores the flag.
  bool get _enforcesWifi => switch (_recognizer) {
    RecognizerModelAdmin(:final enforcesWifiOnly) => enforcesWifiOnly,
    _ => true,
  };

  ModelDownloadState stateOf(String tag) {
    final d = _active[tag];
    if (d != null) {
      return d.waitingForWifi && !d.cellular
          ? ModelDownloadState.waitingForWifi
          : ModelDownloadState.downloading;
    }
    return _failed.contains(tag)
        ? ModelDownloadState.failed
        : ModelDownloadState.none;
  }

  /// iOS: automatic indexing was turned on while the model is missing.
  bool isHighlighted(String tag) => _highlighted.contains(tag);

  void highlight(String tag) {
    if (_disposed || _active.containsKey(tag) || !_highlighted.add(tag)) {
      return;
    }
    notifyListeners();
  }

  /// ensureModel(tag, wifiOnly:) — or joins the running download of [tag].
  /// Completes (never with an error) when the download ends.
  Future<void> start(String tag, {required bool wifiOnly}) {
    if (_disposed) return Future<void>.value();
    final running = _active[tag];
    if (running != null) return running.done.future;
    final d = _Download();
    _active[tag] = d;
    _failed.remove(tag);
    _highlighted.remove(tag);
    if (wifiOnly && _enforcesWifi) {
      d.wifiTimer = Timer(kWifiWaitBeforeCellular, () {
        if (_disposed || !identical(_active[tag], d)) return;
        d.waitingForWifi = true;
        notifyListeners();
      });
    }
    _run(tag, d, wifiOnly: wifiOnly);
    notifyListeners();
    return d.done.future;
  }

  /// [지금 셀룰러로 받기] (after its second press): an unconditioned download
  /// beside the waiting one. Without a running download it starts one.
  Future<void> startCellular(String tag) {
    if (_disposed) return Future<void>.value();
    final d = _active[tag];
    if (d == null) return start(tag, wifiOnly: false);
    if (!d.cellular) {
      d.cellular = true;
      _run(tag, d, wifiOnly: false);
      notifyListeners();
    }
    return d.done.future;
  }

  void _run(String tag, _Download d, {required bool wifiOnly}) {
    d.running++;
    unawaited(
      _recognizer
          .ensureModel(tag, wifiOnly: wifiOnly)
          .then<void>(
            (_) => _ended(tag, d, wifiOnly: wifiOnly),
            onError: (Object e, StackTrace s) =>
                _ended(tag, d, wifiOnly: wifiOnly, error: e, stack: s),
          ),
    );
  }

  void _ended(
    String tag,
    _Download d, {
    required bool wifiOnly,
    Object? error,
    StackTrace? stack,
  }) {
    d.running--;
    if (_disposed || !identical(_active[tag], d)) return;
    if (error != null) {
      if (error is! RecognizerUnsupported) {
        reportRecognitionError(
          error,
          stack!,
          'handwriting model $tag download',
        );
      }
      if (d.running > 0) {
        // The other request goes on (a failed cellular try: back to waiting).
        if (!wifiOnly) d.cellular = false;
        notifyListeners();
        return;
      }
      _failed.add(tag);
    }
    _active.remove(tag);
    d.wifiTimer?.cancel();
    d.done.complete();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final d in _active.values) {
      d.wifiTimer?.cancel();
      if (!d.done.isCompleted) d.done.complete();
    }
    _active.clear();
    super.dispose();
  }
}

/// The container's user downloads (follows the handwriting engine).
final modelDownloadsProvider = Provider<ModelDownloads>((ref) {
  final downloads = ModelDownloads(ref.watch(handwritingRecognizerProvider));
  ref.onDispose(downloads.dispose);
  return downloads;
}, name: 'modelDownloadsProvider');
