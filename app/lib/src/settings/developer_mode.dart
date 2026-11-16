/// (v2.14-ui, UI stage 1 — m5-7/01-infra 'UI 정리 1단계') Developer mode: the
/// developer-only settings (storage diagnostics, 품질 실험, 개발자 표시, 기능
/// 켜고 끄기, 이전 판 DB 사본, renderer / startup / 진단 정보 복사) and the
/// editor's ⋯ '개발자 표시' show only in it.
///
/// It is on while any of these holds:
/// - the stored device setting `app.developerMode` (settings › 정보 › the 빌드
///   row tapped [DeveloperModeTapCounter.tapsToToggle] times toggles it);
/// - the developer overlay is on (EditorSettings.showDevOverlay — ⌘⇧D /
///   Ctrl+Shift+D keep working and bring the developer items with them);
/// - `?dev=1` in the page address (web; never stored).
///
/// The packages read CORE's `developerModeProvider` (contract
/// m5-7/00-overview 'v2.14-ui'); the shell overrides it with
/// [appDeveloperModeProvider] ([developerModeOverride]).
library;

import 'dart:async';

import 'package:feature_editor/feature_editor.dart' show editorSettingsProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart';

/// The stored switch (device scope — never synced).
abstract final class AppDeveloperModeKeys {
  static final SettingKey<bool> enabled = SettingKey.boolean(
    'app.developerMode',
    false,
    scope: SettingScope.device,
  );
}

/// `?dev=1` in the page address (read once; web only in practice).
final appDevUrlFlagProvider = Provider<bool>(
  (ref) => Uri.base.queryParameters['dev'] == '1',
  name: 'appDevUrlFlagProvider',
);

/// The stored switch, false while the settings load.
final appDeveloperModeStoredProvider = Provider<bool>(
  (ref) =>
      ref
          .watch(settingsSnapshotProvider)
          .value
          ?.get(AppDeveloperModeKeys.enabled) ??
      false,
  name: 'appDeveloperModeStoredProvider',
);

/// Stored switch ∨ developer overlay on ∨ `?dev=1`.
final appDeveloperModeProvider = Provider<bool>(
  (ref) =>
      ref.watch(appDeveloperModeStoredProvider) ||
      ref.watch(editorSettingsProvider.select((s) => s.showDevOverlay)) ||
      ref.watch(appDevUrlFlagProvider),
  name: 'appDeveloperModeProvider',
);

/// The root override that hands [appDeveloperModeProvider] to the packages.
Override developerModeOverride() => developerModeProvider.overrideWith(
  (ref) => ref.watch(appDeveloperModeProvider),
);

/// Flips the stored switch; returns its new value.
Future<bool> toggleStoredDeveloperMode(SettingsRepository settings) async {
  final next = !await settings.get(AppDeveloperModeKeys.enabled);
  await settings.set(AppDeveloperModeKeys.enabled, next);
  return next;
}

/// Counts taps on the 빌드 row: [tapsToToggle] taps, each within [window] of
/// the one before, make one toggle (then it starts again).
final class DeveloperModeTapCounter {
  DeveloperModeTapCounter({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const int tapsToToggle = 7;

  /// (v2.14-ui review) From this tap on, the 빌드 row says how many are left.
  static const int hintFrom = 4;
  static const Duration window = Duration(seconds: 2);

  final DateTime Function() _now;
  int _count = 0;
  DateTime? _last;

  /// Taps so far in the current run.
  int get count => _count;

  /// Records a tap; true on the [tapsToToggle]th.
  bool tap() {
    final now = _now();
    final last = _last;
    if (last == null || now.difference(last) > window) _count = 0;
    _last = now;
    _count++;
    if (_count < tapsToToggle) return false;
    _count = 0;
    _last = null;
    return true;
  }
}
