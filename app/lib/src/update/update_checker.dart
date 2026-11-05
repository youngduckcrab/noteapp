/// New-version detection (docs/plans/01-infra.md 4.5.7, 6.11 D7).
///
/// An iPad home-screen app does not re-read the page when it comes back from
/// the background, so the shell polls `/build_info.json` (written next to
/// `index.html` by `ws finalize-web`) and shows [UpdateBanner] when the
/// served build differs from the compiled one. It never reloads by itself
/// (a reload in the middle of handwriting would lose the stroke).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../runtime/build_info.dart';
import '../web/web_platform.dart';

@immutable
final class UpdateCheckConfig {
  const UpdateCheckConfig({
    this.initialDelay = const Duration(seconds: 5),
    this.interval = const Duration(minutes: 10),
    this.minGapOnResume = const Duration(seconds: 60),
    this.fetchTimeout = const Duration(seconds: 5),
    this.path = 'build_info.json',
  });
  final Duration initialDelay;
  final Duration interval;
  final Duration minGapOnResume;
  final Duration fetchTimeout;
  final String path;
}

sealed class UpdateStatus {
  const UpdateStatus();
}

/// Non-web, local build, or channel == local.
final class UpdateDisabled extends UpdateStatus {
  const UpdateDisabled();
}

final class UpdateUnknown extends UpdateStatus {
  const UpdateUnknown();
}

final class UpdateUpToDate extends UpdateStatus {
  const UpdateUpToDate(this.checkedAt);
  final DateTime checkedAt;
}

final class UpdateAvailable extends UpdateStatus {
  const UpdateAvailable(this.remote);
  final BuildInfo remote;
}

final class UpdateDismissed extends UpdateStatus {
  const UpdateDismissed(this.remote);
  final BuildInfo remote;
}

/// Algorithm (6.11):
///
/// 1. Disabled off the web, for a local build and for channel `local`.
/// 2. Otherwise [UpdateUnknown]; the first check runs after
///    [UpdateCheckConfig.initialDelay], then every
///    [UpdateCheckConfig.interval] while the page is visible. A `visible`
///    event checks again when the last check is older than
///    [UpdateCheckConfig.minGapOnResume].
/// 3. A failed fetch (null, bad JSON, no sha) keeps the status (debug print
///    only, nothing in the error log).
/// 4. Same sha → [UpdateUpToDate]; another sha → [UpdateAvailable], or
///    [UpdateDismissed] when the user dismissed that sha.
///
/// Elapsed time is measured with timers only (no wall clock), so fake_async
/// drives every rule.
class UpdateChecker extends Notifier<UpdateStatus> {
  late UpdateCheckConfig _config;
  late WebPlatform _web;
  late BuildInfo _local;

  Timer? _initial;
  Timer? _periodic;

  /// Active for [UpdateCheckConfig.minGapOnResume] after a check started.
  Timer? _recent;
  StreamSubscription<WebVisibility>? _visibility;
  bool _visible = true;
  Future<void>? _inFlight;
  String? _dismissedSha;
  bool _applying = false;

  @override
  UpdateStatus build() {
    _local = ref.watch(buildInfoProvider);
    final runtime = ref.watch(runtimeInfoProvider);
    _dismissedSha = null;
    _inFlight = null;
    _visible = true;
    if (!runtime.isWeb ||
        _local.isLocal ||
        _local.channel == BuildChannel.local) {
      return const UpdateDisabled();
    }
    _config = ref.watch(updateCheckConfigProvider);
    _web = ref.watch(webPlatformProvider);

    _initial = Timer(_config.initialDelay, () {
      _initial = null;
      _periodic = Timer.periodic(_config.interval, (_) => _scheduledCheck());
      _scheduledCheck();
    });
    _visibility = _web.visibilityChanges.listen(_onVisibility);
    ref.onDispose(() {
      _initial?.cancel();
      _initial = null;
      _periodic?.cancel();
      _periodic = null;
      _recent?.cancel();
      _recent = null;
      unawaited(_visibility?.cancel());
      _visibility = null;
    });
    return const UpdateUnknown();
  }

  /// Fetch now, ignoring throttling. Never throws.
  Future<void> checkNow() {
    if (state is UpdateDisabled) return Future<void>.value();
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  /// Hide the banner until a build with another sha appears.
  void dismiss() {
    if (state case UpdateAvailable(:final remote)) {
      _dismissedSha = remote.gitSha;
      state = UpdateDismissed(remote);
    }
  }

  /// notifyAppHidden() (flush) then WebPlatform.reload().
  Future<void> applyUpdate() async {
    if (_applying) return;
    _applying = true;
    final web = ref.read(webPlatformProvider);
    try {
      // AppBootstrapper.notifyAppHidden gives each module 500 ms and never
      // throws; the catch only covers a container without a bootstrapper.
      await ref.read(appBootstrapperProvider).notifyAppHidden();
    } on Object catch (error) {
      _debug('flush before reload failed: $error');
    }
    try {
      web.reload();
    } finally {
      _applying = false;
    }
  }

  void _onVisibility(WebVisibility visibility) {
    _visible = visibility == WebVisibility.visible;
    if (!_visible) return;
    // Before the first scheduled check the initial timer covers it.
    if (_initial != null) return;
    if (_recent?.isActive ?? false) return;
    unawaited(checkNow());
  }

  void _scheduledCheck() {
    if (!_visible) return;
    unawaited(checkNow());
  }

  Future<void> _check() async {
    _recent?.cancel();
    _recent = Timer(_config.minGapOnResume, () {});
    final BuildInfo remote;
    try {
      final text = await _web.fetchTextNoStore(
        _config.path,
        timeout: _config.fetchTimeout,
      );
      if (text == null) {
        _debug('${_config.path}: no response');
        return;
      }
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) {
        _debug('${_config.path}: not a JSON object');
        return;
      }
      remote = BuildInfo.fromJson(json);
    } on Object catch (error) {
      _debug('${_config.path}: $error');
      return;
    }
    if (!ref.mounted) return;
    if (remote.gitSha == _local.gitSha) {
      state = UpdateUpToDate(DateTime.now());
    } else if (remote.gitSha == _dismissedSha) {
      state = UpdateDismissed(remote);
    } else {
      state = UpdateAvailable(remote);
    }
  }

  static void _debug(String message) {
    if (kDebugMode) debugPrint('UpdateChecker: $message');
  }
}

final updateCheckConfigProvider = Provider<UpdateCheckConfig>(
  (ref) => const UpdateCheckConfig(),
  name: 'updateCheckConfigProvider',
);

final updateCheckerProvider = NotifierProvider<UpdateChecker, UpdateStatus>(
  UpdateChecker.new,
  name: 'updateCheckerProvider',
);
