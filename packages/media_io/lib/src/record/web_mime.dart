// lib/src/record/web_mime.dart — the web recorder's MIME candidates (m5-7/06-pdf 6.8.1). Pure Dart:
// the browser engine (recorder_engine_browser.dart) probes MediaRecorder.isTypeSupported once
// per candidate (WebMimeTable.probe — initializeMediaIo's web step, 4.2.1) and chooses from that
// table; tests give the support set by hand. Internal.
//
// | # | candidate                    | condition                                   | playable |
// | 1 | audio/mp4;codecs=mp4a.40.2   | supported                                   | true     |
// | 2 | audio/mp4;codecs=mp4a        | supported                                   | true     |
// | 3 | audio/mp4                    | supported and neither 4 nor 5 is supported  | true*    |
// | 4 | audio/webm;codecs=opus       | supported and allowNonAacOnWeb              | false    |
// | 5 | audio/webm                   | supported and allowNonAacOnWeb              | false    |
//
// * 3 (an mp4 that names no codec — old Safari) turns false when the recorder's actual MIME says
// opus (Linux Chrome puts opus into audio/mp4 — 조사 02 3.2). Chrome therefore records 4.
import 'package:flutter/foundation.dart';

/// The candidates of 6.8.1, in order.
const List<String> webMimeCandidates = [
  'audio/mp4;codecs=mp4a.40.2',
  'audio/mp4;codecs=mp4a',
  'audio/mp4',
  'audio/webm;codecs=opus',
  'audio/webm',
];

/// The MIME a web recording asks MediaRecorder for, and what follows from it.
@immutable
final class WebMimeChoice {
  const WebMimeChoice({
    required this.mimeType,
    required this.crossPlatformPlayable,
    required this.extension,
  });

  final String mimeType;

  /// false: the iPad app may not play it (opus / WebM — the panel's 웹 형식 경고).
  final bool crossPlatformPlayable;

  /// '.m4a' or '.webm' (6.8.1 — the download file name, 6.10.4).
  final String extension;

  @override
  bool operator ==(Object other) =>
      other is WebMimeChoice &&
      other.mimeType == mimeType &&
      other.crossPlatformPlayable == crossPlatformPlayable &&
      other.extension == extension;

  @override
  int get hashCode => Object.hash(mimeType, crossPlatformPlayable, extension);

  @override
  String toString() =>
      'WebMimeChoice($mimeType, playable: $crossPlatformPlayable, $extension)';
}

/// The browser's answer for each candidate of [webMimeCandidates].
@immutable
final class WebMimeTable {
  WebMimeTable(Map<String, bool> supported)
    : supported = Map.unmodifiable({
        for (final c in webMimeCandidates) c: supported[c] ?? false,
      });

  /// Asks [isTypeSupported] once per candidate (a throwing probe counts as not supported).
  factory WebMimeTable.probe(bool Function(String mimeType) isTypeSupported) =>
      WebMimeTable({
        for (final c in webMimeCandidates) c: _safely(isTypeSupported, c),
      });

  /// Candidate → supported, for every candidate.
  final Map<String, bool> supported;

  bool _has(int i) => supported[webMimeCandidates[i]]!;

  /// The 6.8.1 choice; `null` = nothing to record here (checkSupport → unsupported).
  WebMimeChoice? choose({required bool allowNonAacOnWeb}) {
    if (_has(0)) return _mp4(webMimeCandidates[0]);
    if (_has(1)) return _mp4(webMimeCandidates[1]);
    final webm = _has(3) || _has(4);
    if (_has(2) && !webm) return _mp4(webMimeCandidates[2]);
    if (!allowNonAacOnWeb) return null;
    if (_has(3)) return _webm(webMimeCandidates[3]);
    if (_has(4)) return _webm(webMimeCandidates[4]);
    return null;
  }

  /// The developer overlay's encoder part (6.14 `enc:` — web): `mp4a=no mp4=yes webm/opus=yes`.
  String get encoderLine {
    String yn(bool b) => b ? 'yes' : 'no';
    return 'mp4a=${yn(_has(0) || _has(1))} mp4=${yn(_has(2))} '
        'webm/opus=${yn(_has(3))}';
  }

  @override
  bool operator ==(Object other) =>
      other is WebMimeTable && mapEquals(other.supported, supported);

  @override
  int get hashCode =>
      Object.hashAll([for (final c in webMimeCandidates) supported[c]]);

  @override
  String toString() => 'WebMimeTable($encoderLine)';
}

/// After MediaRecorder started: the MIME it actually writes ([actual] — '' when the browser does
/// not say) with crossPlatformPlayable and the extension following it (6.8.1 note on 3).
WebMimeChoice choiceForActual(WebMimeChoice chosen, String actual) {
  final mime = actual.trim().isEmpty ? chosen.mimeType : actual.trim();
  final lower = mime.toLowerCase();
  final webm = lower.contains('webm');
  final opus = lower.contains('opus');
  return WebMimeChoice(
    mimeType: mime,
    crossPlatformPlayable: webm || opus
        ? false
        : (lower.contains('mp4') ? true : chosen.crossPlatformPlayable),
    extension: webm
        ? '.webm'
        : (lower.contains('mp4') ? '.m4a' : chosen.extension),
  );
}

WebMimeChoice _mp4(String mime) => WebMimeChoice(
  mimeType: mime,
  crossPlatformPlayable: true,
  extension: '.m4a',
);

WebMimeChoice _webm(String mime) => WebMimeChoice(
  mimeType: mime,
  crossPlatformPlayable: false,
  extension: '.webm',
);

bool _safely(bool Function(String) probe, String mime) {
  try {
    return probe(mime);
  } on Object {
    return false;
  }
}
