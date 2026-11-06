// lib/src/ui/model_row.dart — (internal) m5-7/05-library 6.18 '인식 모델'
// rows (the lab's two rows reuse it — 6.20, review S-10): one language's
// model state and its button.
//
//   준비됨 [지우기]            (the engine has RecognizerModelAdmin)
//   받지 않음 [받기]            iPad with recog.modelWifiOnly: two presses —
//                               the first turns the button into the
//                               cellular warning (6.7.4, 6.12: no dialog)
//   받는 중…                    a download runs (here or in the engine)
//   와이파이에 연결되면 받아요. [지금 셀룰러로 받기]
//                               Android: a Wi-Fi-only download still runs
//                               after 5 s; two presses → wifiOnly: false
//   받지 못했어요 [다시]        the last download failed (6.22)
//   쓸 수 없음                  unsupported engine / disabled row
//
// The state is modelState(tag), asked when the row opens, on the engine's
// modelChanges for the tag and whenever the tag's user download changes
// (ModelDownloads — shared by every row of the container).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import '../model/candidates.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/model_admin.dart';
import '../providers.dart';
import '../settings/recognition_settings_keys.dart';
import 'model_downloads.dart';

/// The row's key is `'<keyPrefix>.<tag>'`, its cellular button's
/// `'<keyPrefix>.<tag>.cellular'` (appendix C — settings:
/// `recog.settings.model`).
class RecognitionModelRow extends ConsumerStatefulWidget {
  const RecognitionModelRow({
    super.key,
    required this.languageTag,
    this.enabled = true,
    this.keyPrefix = 'recog.settings.model',
  });

  final String languageTag;

  /// false → '쓸 수 없음' and no button (the web, no engine).
  final bool enabled;
  final String keyPrefix;

  @override
  ConsumerState<RecognitionModelRow> createState() =>
      _RecognitionModelRowState();
}

class _RecognitionModelRowState extends ConsumerState<RecognitionModelRow> {
  HandwritingRecognizer? _recognizer;
  StreamSubscription<String>? _changes;
  ModelDownloads? _downloads;
  ModelDownloadState _download = ModelDownloadState.none;
  RecognitionModelState? _model;
  int _ask = 0;

  /// The two-press button's first press happened (6.12).
  bool _confirming = false;

  String get _tag => widget.languageTag;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      handwritingRecognizerProvider,
      (_, next) => _watchEngine(next),
      fireImmediately: true,
    );
    ref.listenManual(
      modelDownloadsProvider,
      (_, next) => _watchDownloads(next),
      fireImmediately: true,
    );
  }

  void _watchEngine(HandwritingRecognizer recognizer) {
    unawaited(_changes?.cancel()); // never awaited (fake_async)
    _changes = null;
    _recognizer = recognizer;
    if (recognizer case final RecognizerModelAdmin admin) {
      _changes = admin.modelChanges.listen((tag) {
        if (tag == _tag) _askModel();
      });
    }
    _askModel();
  }

  void _watchDownloads(ModelDownloads downloads) {
    _downloads?.removeListener(_onDownloads);
    _downloads = downloads..addListener(_onDownloads);
    _download = downloads.stateOf(_tag);
    if (mounted) setState(() {});
  }

  void _onDownloads() {
    if (!mounted) return;
    final state = _downloads!.stateOf(_tag);
    setState(() {
      if (state != _download) {
        _download = state;
        _confirming = false;
        _askModel();
      }
    });
  }

  void _askModel() {
    final recognizer = _recognizer;
    if (recognizer == null) return;
    final ask = ++_ask;
    unawaited(
      recognizer
          .modelState(_tag)
          .then<void>(
            (state) {
              if (mounted && ask == _ask) setState(() => _model = state);
            },
            onError: (Object e, StackTrace s) {
              if (!mounted || ask != _ask) return;
              reportRecognitionError(e, s, 'handwriting model $_tag state');
              setState(() => _model = RecognitionModelState.notDownloaded);
            },
          ),
    );
  }

  @override
  void didUpdateWidget(RecognitionModelRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.languageTag != widget.languageTag) {
      _download = _downloads?.stateOf(_tag) ?? ModelDownloadState.none;
      _confirming = false;
      _model = null;
      _askModel();
    }
  }

  @override
  void dispose() {
    _downloads?.removeListener(_onDownloads);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  /// iPad: the engine ignores wifiOnly, so the app asks first (6.7.4).
  bool get _asksFirst => switch (_recognizer) {
    RecognizerModelAdmin(enforcesWifiOnly: false) => true,
    _ => false,
  };

  void _startDownload(bool wifiOnly) {
    if (_asksFirst && wifiOnly && !_confirming) {
      setState(() => _confirming = true);
      return;
    }
    // iPad after the warning: the user accepted cellular data.
    unawaited(_downloads!.start(_tag, wifiOnly: _asksFirst ? false : wifiOnly));
  }

  void _cellular() {
    if (!_confirming) {
      setState(() => _confirming = true);
      return;
    }
    unawaited(_downloads!.startCellular(_tag));
  }

  void _delete() {
    if (_recognizer case final RecognizerModelAdmin admin) {
      _deleteWith(admin);
    }
  }

  void _deleteWith(RecognizerModelAdmin admin) {
    unawaited(
      admin
          .deleteModel(_tag)
          .then<void>(
            (_) {},
            onError: (Object e, StackTrace s) =>
                reportRecognitionError(e, s, 'handwriting model $_tag delete'),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wifiOnly = ref.watch(
      core.settingsSnapshotProvider.select(
        (s) => (s.value ?? const core.SettingsSnapshot({})).get(
          RecognitionSettingsKeys.modelWifiOnly,
        ),
      ),
    );
    final highlighted = _downloads?.isHighlighted(_tag) ?? false;
    final hasAdmin = _recognizer is RecognizerModelAdmin;
    String? status;
    Widget? button;

    Widget outlined(String label, VoidCallback onPressed, {Key? key}) =>
        OutlinedButton(key: key, onPressed: onPressed, child: Text(label));

    if (!widget.enabled || _model == RecognitionModelState.unsupported) {
      status = RecognitionStrings.modelUnsupported;
    } else {
      switch (_download) {
        case ModelDownloadState.downloading:
          status = RecognitionStrings.modelDownloading;
        case ModelDownloadState.waitingForWifi:
          status = RecognitionStrings.waitingForWifi;
          button = outlined(
            _confirming
                ? RecognitionStrings.cellularConfirm
                : RecognitionStrings.downloadOnCellular,
            _cellular,
            key: ValueKey('${widget.keyPrefix}.$_tag.cellular'),
          );
        case ModelDownloadState.failed:
          status = RecognitionStrings.modelFailed;
          button = outlined(
            _confirming
                ? RecognitionStrings.cellularWarning
                : RecognitionStrings.retry,
            () => _startDownload(wifiOnly),
          );
        case ModelDownloadState.none:
          switch (_model) {
            case null:
              break;
            case RecognitionModelState.ready:
              status = RecognitionStrings.modelReady;
              if (hasAdmin) {
                button = outlined(RecognitionStrings.deleteModel, _delete);
              }
            case RecognitionModelState.downloading:
              status = RecognitionStrings.modelDownloading;
            case RecognitionModelState.notDownloaded:
              status = RecognitionStrings.modelNotDownloaded;
              final label = _confirming
                  ? RecognitionStrings.cellularWarning
                  : RecognitionStrings.download;
              void press() => _startDownload(wifiOnly);
              button = highlighted
                  ? FilledButton(onPressed: press, child: Text(label))
                  : outlined(label, press);
            case RecognitionModelState.unsupported:
              status = RecognitionStrings.modelUnsupported;
          }
      }
    }

    return Column(
      key: ValueKey('${widget.keyPrefix}.$_tag'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          enabled: widget.enabled,
          title: Text(RecognitionStrings.languageLabel(_tag)),
          subtitle: status == null ? null : Text(status),
        ),
        if (button != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: button,
            ),
          ),
      ],
    );
  }
}
