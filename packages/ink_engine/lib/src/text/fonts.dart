// lib/src/text/fonts.dart — contract 7.2.9 (m5-7/03-ink 4.9, rules 4.10, 6.10.1). Final
// (T26a).
//
// NoteSans is NOT in FontManifest (no download at web start, 7.4.5): the two
// files are read with rootBundle when a text box is first drawn / measured /
// exported and registered with one FontLoader('NoteSans'). Every load is
// bounded by InkTuning.fontLoadTimeoutMs (rootBundle does not answer under
// `flutter test --platform chrome` — those tests call useInkTestFonts()).
// After a failure, implicit loads (measure, measureSync, rasterize, painting,
// thumbnails) wait InkTuning.fontRetryAfterMs before starting a new one; a
// direct ensureLoaded() always tries again.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import '../tuning.dart';
import 'note_sans_coverage.dart';

/// Reads the bytes of one NoteSans file (bold or regular).
typedef InkFontSource = Future<Uint8List> Function({required bool bold});

abstract final class InkFonts {
  /// text boxes; packages/ink_engine/assets/fonts/
  static const String noteSans = 'NoteSans';

  /// Lazy FontLoader — not in FontManifest (no startup download). Loads the regular and the
  /// bold file at once and remembers the Future. A failure (or InkTuning.fontLoadTimeoutMs,
  /// 5 s → TimeoutException) ends it with that error and forgets the Future, so the next
  /// call tries again; bytes that arrive after the timeout are dropped.
  static Future<void> ensureLoaded() => _fonts.ensureLoaded();

  /// The file bytes for PDF embedding (regular or bold). Same 5 s limit
  /// (TimeoutException); read once, then answered at once.
  static Future<Uint8List> noteSansBytes({bool bold = false}) =>
      _fonts.bytesWithTimeout(bold);

  /// Every char in the bundled subset? Spaces and control characters count as covered;
  /// the table is the real subset's even with the test font installed.
  static bool covers(String text) {
    for (final rune in text.runes) {
      if (rune <= 0x20 || (rune >= 0x7F && rune < 0xA0)) continue;
      if (rune == 0x2028 || rune == 0x2029) continue;
      if (!_inCoverage(rune)) return false;
    }
    return true;
  }

  static bool _inCoverage(int cp) {
    const table = noteSansCoverage;
    var lo = 0, hi = table.length ~/ 2 - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final start = table[2 * mid], end = table[2 * mid + 1];
      if (cp < start) {
        hi = mid - 1;
      } else if (cp > end) {
        lo = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }
}

/// The asset keys (the package key works in the app and in package tests alike).
const String _regularAsset =
    'packages/ink_engine/assets/fonts/NoteSans-Regular.ttf';
const String _boldAsset = 'packages/ink_engine/assets/fonts/NoteSans-Bold.ttf';

Future<Uint8List> _rootBundleSource({required bool bold}) async {
  final data = await rootBundle.load(bold ? _boldAsset : _regularAsset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

final _FontState _fonts = _FontState();

final class _FontState {
  InkFontSource? _debugSource;

  /// Bumped by debugSetInkFontSource / the test reset: late results of an older
  /// generation are dropped.
  int _generation = 0;
  bool _loaded = false;
  Future<void>? _loading;

  /// The last load attempt failed (and none is running).
  bool _failed = false;

  /// When it failed (InkFontsDebug.nowUs), for the implicit retry pause.
  int? _failedAtUs;
  final Map<bool, Future<Uint8List>> _bytes = {};

  Duration get _timeout =>
      const Duration(milliseconds: InkTuning.fontLoadTimeoutMs);

  InkFontSource get _source => _debugSource ?? _rootBundleSource;

  /// The bytes of one file, read once (an error or a timeout forgets the Future).
  Future<Uint8List> _read(bool bold) {
    final cached = _bytes[bold];
    if (cached != null) return cached;
    final gen = _generation;
    final f = Future<Uint8List>.sync(() => _source(bold: bold));
    _bytes[bold] = f;
    f.then<void>(
      (_) {},
      onError: (Object _) {
        if (gen == _generation && identical(_bytes[bold], f)) {
          _bytes.remove(bold);
        }
      },
    );
    return f;
  }

  void _dropInflight(int gen) {
    if (gen != _generation) return;
    _bytes.clear();
  }

  Future<Uint8List> bytesWithTimeout(bool bold) {
    final gen = _generation;
    return _read(bold).timeout(
      _timeout,
      onTimeout: () {
        _dropInflight(gen);
        throw TimeoutException(
          'NoteSans ${bold ? 'bold' : 'regular'} bytes did not arrive in '
          '${InkTuning.fontLoadTimeoutMs} ms',
          _timeout,
        );
      },
    );
  }

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final running = _loading;
    if (running != null) return running;
    final gen = _generation;
    var abandoned = false;
    _failed = false;
    final work = () async {
      final bytes = await Future.wait([_read(false), _read(true)]);
      if (abandoned || gen != _generation) return;
      final loader = FontLoader(InkFonts.noteSans)
        ..addFont(Future.value(ByteData.sublistView(bytes[0])))
        ..addFont(Future.value(ByteData.sublistView(bytes[1])));
      await loader.load();
    }();
    final bounded = work.timeout(
      _timeout,
      onTimeout: () {
        abandoned = true;
        _dropInflight(gen);
        throw TimeoutException(
          'NoteSans fonts did not load in ${InkTuning.fontLoadTimeoutMs} ms',
          _timeout,
        );
      },
    );
    final f = bounded.then<void>(
      (_) {
        if (gen != _generation) return;
        _loaded = true;
        _loading = null;
        _failed = false;
        _failedAtUs = null;
      },
      onError: (Object error, StackTrace stack) {
        if (gen == _generation) {
          _loading = null;
          _failed = true;
          _failedAtUs = InkFontsDebug.nowUs();
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _loading = f;
    return f;
  }

  /// Implicit load (measure, painting, thumbnails): never throws; after a failure no
  /// new load starts for InkTuning.fontRetryAfterMs.
  Future<void> loadImplicitly() {
    if (_loaded) return Future<void>.value();
    final running = _loading;
    if (running != null) return running.catchError((Object _) {});
    if (_coolingDown) return Future<void>.value();
    return ensureLoaded().catchError((Object _) {});
  }

  bool get _coolingDown {
    final at = _failedAtUs;
    if (!_failed || at == null) return false;
    return InkFontsDebug.nowUs() - at < InkTuning.fontRetryAfterMs * 1000;
  }

  /// Loaded, or the last attempt ended in a failure and none is running
  /// (measureSync gives the fallback-font value then).
  bool get settled => _loaded || (_failed && _loading == null);

  void setSource(InkFontSource? source) {
    _debugSource = source;
    reset();
  }

  void reset() {
    _generation++;
    _loaded = false;
    _loading = null;
    _failed = false;
    _failedAtUs = null;
    _bytes.clear();
  }
}

/// INTERNAL state access for INK's text code and tests (not exported).
@internal
abstract final class InkFontsDebug {
  /// The clock of the implicit retry pause (µs). Tests replace it (fake_async).
  static int Function() nowUs = _stopwatchUs;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int _stopwatchUs() => _stopwatch.elapsedMicroseconds;

  /// NoteSans is registered (text is laid out with it).
  static bool get isLoaded => _fonts._loaded;

  /// See _FontState.settled.
  static bool get isSettled => _fonts.settled;

  /// A load is running.
  static bool get isLoading => _fonts._loading != null;

  /// Implicit load — never throws, honours the retry pause.
  static Future<void> loadImplicitly() => _fonts.loadImplicitly();

  /// The current byte source (null = rootBundle).
  static InkFontSource? get source => _fonts._debugSource;

  /// testing.dart debugSetInkFontSource: a new source, the state starts over.
  static void setSource(InkFontSource? source) => _fonts.setSource(source);

  /// Forgets everything (tests): not loaded, no failure, no cached bytes; the source and
  /// [nowUs] are kept.
  static void reset() => _fonts.reset();
}
