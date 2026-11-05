// UpdateChecker (docs/plans/01-infra.md 4.5.7, 6.11, 9.1). Time is fake
// (fake_async): the checker measures time with timers only.
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/update/update_checker.dart';
import 'package:noteapp/src/web/web_platform.dart';

import '../fakes/fake_app_module.dart';
import '../fakes/fake_web_platform.dart';

final String _localSha = 'a' * 40;
final String _remoteSha = 'b2c3d4e${'f' * 33}';
final String _otherSha = 'c' * 40;

BuildInfo _build({
  required String sha,
  int buildNumber = 42,
  BuildChannel channel = BuildChannel.preview,
}) => BuildInfo(
  version: '0.1.0',
  buildNumber: buildNumber,
  gitSha: sha,
  gitRef: 'main',
  channel: channel,
);

String _json(BuildInfo info) => jsonEncode(info.toJson());

const _web = RuntimeInfo(
  isWeb: true,
  renderer: WebRenderer.canvasKit,
  isStandalone: true,
);

const _native = RuntimeInfo(
  isWeb: false,
  renderer: WebRenderer.notWeb,
  isStandalone: false,
);

final class _Harness {
  _Harness(
    this.async, {
    BuildInfo? local,
    RuntimeInfo runtime = _web,
    UpdateCheckConfig config = const UpdateCheckConfig(),
    Duration hiddenDelay = Duration.zero,
  }) : local = local ?? _build(sha: _localSha) {
    web = FakeWebPlatform(buildInfoJson: _json(this.local));
    module = FakeAppModule(
      id: 'core',
      hiddenDelay: hiddenDelay,
      events: events,
    );
    final bootstrapper = AppBootstrapper(
      modules: [module],
      buildInfo: this.local,
      runtimeInfo: runtime,
      web: web,
      errorLog: errorLog,
      ownerId: kLocalOwnerId,
    );
    unawaited(bootstrapper.run());
    async.flushMicrotasks();
    container = ProviderContainer.test(
      overrides: [
        buildInfoProvider.overrideWithValue(this.local),
        runtimeInfoProvider.overrideWithValue(runtime),
        webPlatformProvider.overrideWithValue(web),
        appErrorLogProvider.overrideWithValue(errorLog),
        appBootstrapperProvider.overrideWithValue(bootstrapper),
        updateCheckConfigProvider.overrideWithValue(config),
      ],
    );
    states = [];
    container.listen<UpdateStatus>(
      updateCheckerProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
  }

  final FakeAsync async;
  final BuildInfo local;
  final AppErrorLog errorLog = AppErrorLog();
  final List<String> events = [];
  late final FakeWebPlatform web;
  late final FakeAppModule module;
  late final ProviderContainer container;
  late final List<UpdateStatus> states;

  UpdateStatus get status => container.read(updateCheckerProvider);
  UpdateChecker get checker => container.read(updateCheckerProvider.notifier);

  void serve(BuildInfo remote) => web.buildInfoJson = _json(remote);

  void elapse(Duration duration) {
    async.elapse(duration);
    async.flushMicrotasks();
  }

  void visibility(WebVisibility value) {
    web.emitVisibility(value);
    async.flushMicrotasks();
  }
}

void main() {
  group('disabled', () {
    for (final (name, local, runtime) in [
      ('a local build', BuildInfo.local, _web),
      (
        'channel local with a real sha',
        _build(sha: _localSha, channel: BuildChannel.local),
        _web,
      ),
      ('off the web', _build(sha: _localSha), _native),
    ]) {
      test('$name → UpdateDisabled, nothing fetched or listened to', () {
        fakeAsync((async) {
          final h = _Harness(async, local: local, runtime: runtime);
          expect(h.status, isA<UpdateDisabled>());
          expect(h.web.hasVisibilityListener, isFalse);
          h.elapse(const Duration(hours: 1));
          h.visibility(WebVisibility.hidden);
          h.visibility(WebVisibility.visible);
          unawaited(h.checker.checkNow());
          h.elapse(const Duration(seconds: 1));
          expect(h.web.fetchCount, 0);
          expect(h.status, isA<UpdateDisabled>());
          expect(async.pendingTimers, isEmpty);
        });
      });
    }

    test('live and experiment channels are enabled', () {
      fakeAsync((async) {
        for (final channel in [BuildChannel.live, BuildChannel.experiment]) {
          final h = _Harness(
            async,
            local: _build(sha: _localSha, channel: channel),
          );
          expect(h.status, isA<UpdateUnknown>());
        }
      });
    });
  });

  group('first check', () {
    test('UpdateUnknown until the 5 s initial delay, then the configured '
        'path with the 5 s fetch timeout', () {
      fakeAsync((async) {
        final h = _Harness(async);
        expect(h.status, isA<UpdateUnknown>());
        h.elapse(const Duration(milliseconds: 4999));
        expect(h.web.fetchCount, 0);
        expect(h.status, isA<UpdateUnknown>());
        h.elapse(const Duration(milliseconds: 1));
        expect(h.web.fetchCount, 1);
        expect(h.web.fetchedPaths, ['build_info.json']);
        expect(h.status, isA<UpdateUpToDate>());
      });
    });

    test('same sha → UpdateUpToDate with the check time', () {
      fakeAsync((async) {
        final h = _Harness(async);
        final before = DateTime.now();
        h.elapse(const Duration(seconds: 5));
        final status = h.status as UpdateUpToDate;
        expect(status.checkedAt.isBefore(before), isFalse);
      });
    });

    test('another sha → UpdateAvailable(remote)', () {
      fakeAsync((async) {
        final h = _Harness(async);
        final remote = _build(sha: _remoteSha, buildNumber: 43);
        h.serve(remote);
        h.elapse(const Duration(seconds: 5));
        final status = h.status as UpdateAvailable;
        expect(status.remote, remote);
        expect(status.remote.shortSha, 'b2c3d4e');
        expect(h.errorLog.records, isEmpty);
      });
    });

    test('UpdateCheckConfig defaults (6.11)', () {
      const config = UpdateCheckConfig();
      expect(config.initialDelay, const Duration(seconds: 5));
      expect(config.interval, const Duration(minutes: 10));
      expect(config.minGapOnResume, const Duration(seconds: 60));
      expect(config.fetchTimeout, const Duration(seconds: 5));
      expect(config.path, 'build_info.json');
    });

    test('a configured path is fetched', () {
      fakeAsync((async) {
        final h = _Harness(
          async,
          config: const UpdateCheckConfig(
            initialDelay: Duration(seconds: 1),
            path: 'other/build_info.json',
          ),
        );
        h.web.fetchResponses['other/build_info.json'] = _json(
          _build(sha: _remoteSha),
        );
        h.elapse(const Duration(seconds: 1));
        expect(h.web.fetchedPaths, ['other/build_info.json']);
        expect(h.status, isA<UpdateAvailable>());
      });
    });
  });

  group('schedule', () {
    test('every 10 minutes after the first check while visible', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.elapse(const Duration(seconds: 5));
        expect(h.web.fetchCount, 1);
        h.elapse(const Duration(minutes: 9, seconds: 59));
        expect(h.web.fetchCount, 1);
        h.elapse(const Duration(seconds: 1));
        expect(h.web.fetchCount, 2);
        h.elapse(const Duration(minutes: 10));
        expect(h.web.fetchCount, 3);
        // A new build appears between two periodic checks.
        h.serve(_build(sha: _remoteSha));
        h.elapse(const Duration(minutes: 10));
        expect(h.web.fetchCount, 4);
        expect(h.status, isA<UpdateAvailable>());
      });
    });

    test('no periodic check while hidden', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.elapse(const Duration(seconds: 5));
        expect(h.web.fetchCount, 1);
        h.visibility(WebVisibility.hidden);
        h.elapse(const Duration(hours: 1));
        expect(h.web.fetchCount, 1);
      });
    });

    test('hidden at the initial delay: no first check until visible', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.visibility(WebVisibility.hidden);
        h.elapse(const Duration(minutes: 30));
        expect(h.web.fetchCount, 0);
        h.visibility(WebVisibility.visible);
        expect(h.web.fetchCount, 1);
        expect(h.status, isA<UpdateUpToDate>());
      });
    });

    test('visible before the initial delay waits for the first check', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.elapse(const Duration(seconds: 2));
        h.visibility(WebVisibility.hidden);
        h.visibility(WebVisibility.visible);
        expect(h.web.fetchCount, 0);
        h.elapse(const Duration(seconds: 3));
        expect(h.web.fetchCount, 1);
      });
    });

    test('visible: checks only when the last check is older than 60 s', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.elapse(const Duration(seconds: 5));
        expect(h.web.fetchCount, 1);

        // Back within 60 s of the last check → no check.
        h.visibility(WebVisibility.hidden);
        h.elapse(const Duration(seconds: 59));
        h.visibility(WebVisibility.visible);
        expect(h.web.fetchCount, 1);

        // 60 s after the last check → check.
        h.visibility(WebVisibility.hidden);
        h.elapse(const Duration(seconds: 1));
        h.serve(_build(sha: _remoteSha));
        h.visibility(WebVisibility.visible);
        expect(h.web.fetchCount, 2);
        expect(h.status, isA<UpdateAvailable>());

        // The resume check also counts as the last check.
        h.visibility(WebVisibility.hidden);
        h.elapse(const Duration(seconds: 30));
        h.visibility(WebVisibility.visible);
        expect(h.web.fetchCount, 2);
      });
    });

    test('checkNow ignores the throttle and joins a running fetch', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.elapse(const Duration(seconds: 5));
        expect(h.web.fetchCount, 1);
        h.serve(_build(sha: _remoteSha));
        var done = 0;
        unawaited(h.checker.checkNow().then((_) => done++));
        h.async.flushMicrotasks();
        expect(h.web.fetchCount, 2);
        expect(done, 1);
        expect(h.status, isA<UpdateAvailable>());

        h.web.fetchDelay = const Duration(seconds: 2);
        unawaited(h.checker.checkNow().then((_) => done++));
        unawaited(h.checker.checkNow().then((_) => done++));
        h.async.flushMicrotasks();
        expect(h.web.fetchCount, 3);
        expect(done, 1);
        h.elapse(const Duration(seconds: 2));
        expect(done, 3);
      });
    });

    test('checkNow before the initial delay', () {
      fakeAsync((async) {
        final h = _Harness(async);
        unawaited(h.checker.checkNow());
        h.async.flushMicrotasks();
        expect(h.web.fetchCount, 1);
        expect(h.status, isA<UpdateUpToDate>());
      });
    });
  });

  group('failures keep the status', () {
    for (final (name, body) in [
      ('no response (null)', null),
      ('invalid JSON', '<!doctype html><html></html>'),
      ('not an object', '[1, 2]'),
      ('no APP_GIT_SHA', '{"APP_VERSION": "0.1.0"}'),
    ]) {
      test(name, () {
        fakeAsync((async) {
          final h = _Harness(async);
          h.web.buildInfoJson = body;
          h.elapse(const Duration(seconds: 5));
          expect(h.web.fetchCount, 1);
          expect(h.status, isA<UpdateUnknown>());

          h.serve(_build(sha: _remoteSha));
          unawaited(h.checker.checkNow());
          h.async.flushMicrotasks();
          expect(h.status, isA<UpdateAvailable>());

          h.web.buildInfoJson = body;
          unawaited(h.checker.checkNow());
          h.async.flushMicrotasks();
          expect(h.web.fetchCount, 3);
          expect(h.status, isA<UpdateAvailable>());
          expect(h.errorLog.records, isEmpty);
        });
      });
    }

    test('checkNow never throws (APP_GIT_SHA is not a string)', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.web.buildInfoJson = '{"APP_GIT_SHA": 12}';
        Object? error;
        unawaited(h.checker.checkNow().catchError((Object e) => error = e));
        h.async.flushMicrotasks();
        expect(error, isNull);
        expect(h.status, isA<UpdateUnknown>());
      });
    });
  });

  group('dismiss', () {
    test('hides the same sha, shows a newer one', () {
      fakeAsync((async) {
        final h = _Harness(async);
        final remote = _build(sha: _remoteSha, buildNumber: 43);
        h.serve(remote);
        h.elapse(const Duration(seconds: 5));
        expect(h.status, isA<UpdateAvailable>());

        h.checker.dismiss();
        expect((h.status as UpdateDismissed).remote, remote);

        h.elapse(const Duration(minutes: 10));
        expect(h.web.fetchCount, 2);
        expect((h.status as UpdateDismissed).remote, remote);

        final newer = _build(sha: _otherSha, buildNumber: 44);
        h.serve(newer);
        h.elapse(const Duration(minutes: 10));
        expect((h.status as UpdateAvailable).remote, newer);
      });
    });

    test('does nothing unless an update is shown', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.checker.dismiss();
        expect(h.status, isA<UpdateUnknown>());
        h.elapse(const Duration(seconds: 5));
        h.checker.dismiss();
        expect(h.status, isA<UpdateUpToDate>());
      });
    });

    test('back on the running build → UpdateUpToDate', () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.serve(_build(sha: _remoteSha));
        h.elapse(const Duration(seconds: 5));
        h.checker.dismiss();
        h.serve(h.local);
        h.elapse(const Duration(minutes: 10));
        expect(h.status, isA<UpdateUpToDate>());
      });
    });
  });

  group('applyUpdate', () {
    test('flushes through notifyAppHidden, then reloads', () {
      fakeAsync((async) {
        final h = _Harness(
          async,
          hiddenDelay: const Duration(milliseconds: 300),
        );
        h.serve(_build(sha: _remoteSha));
        h.elapse(const Duration(seconds: 5));
        var done = false;
        unawaited(h.checker.applyUpdate().then((_) => done = true));
        h.async.flushMicrotasks();
        expect(h.module.hiddenCalls, 1);
        expect(h.web.reloadCount, 0);
        h.elapse(const Duration(milliseconds: 299));
        expect(h.web.reloadCount, 0);
        h.elapse(const Duration(milliseconds: 1));
        expect(h.web.reloadCount, 1);
        expect(done, isTrue);
      });
    });

    test('a flush that does not finish waits 500 ms at most', () {
      fakeAsync((async) {
        final h = _Harness(async, hiddenDelay: const Duration(minutes: 1));
        unawaited(h.checker.applyUpdate());
        h.elapse(const Duration(milliseconds: 499));
        expect(h.web.reloadCount, 0);
        h.elapse(const Duration(milliseconds: 1));
        expect(h.web.reloadCount, 1);
        h.elapse(const Duration(minutes: 1));
      });
    });

    test('a second tap while flushing reloads once', () {
      fakeAsync((async) {
        final h = _Harness(
          async,
          hiddenDelay: const Duration(milliseconds: 300),
        );
        unawaited(h.checker.applyUpdate());
        unawaited(h.checker.applyUpdate());
        h.elapse(const Duration(seconds: 1));
        expect(h.module.hiddenCalls, 1);
        expect(h.web.reloadCount, 1);
      });
    });
  });

  test('dispose cancels the timers and the visibility subscription', () {
    fakeAsync((async) {
      final h = _Harness(async);
      expect(h.web.hasVisibilityListener, isTrue);
      h.elapse(const Duration(seconds: 5));
      h.web.fetchDelay = const Duration(seconds: 1);
      unawaited(h.checker.checkNow());
      h.async.flushMicrotasks();
      h.serve(_build(sha: _remoteSha));
      h.container.dispose();
      async.flushMicrotasks();
      expect(h.web.hasVisibilityListener, isFalse);
      // The running fetch ends after dispose without touching the state.
      h.elapse(const Duration(seconds: 1));
      h.elapse(const Duration(hours: 1));
      expect(h.web.fetchCount, 2);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('providers have names (계약 7.4.4)', () {
    expect(updateCheckConfigProvider.name, 'updateCheckConfigProvider');
    expect(updateCheckerProvider.name, 'updateCheckerProvider');
  });
}
