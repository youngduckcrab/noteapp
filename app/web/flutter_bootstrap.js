{{flutter_js}}
{{flutter_build_config}}

// Custom bootstrap (docs/plans/01-infra.md 6.9 'app/web/flutter_bootstrap.js',
// 6.10, 6.11). The two tokens above are replaced by `flutter build web`.
// No --web-define template variables: an undefined one would stay as `{{…}}`
// under `flutter run` and break this script.
(function () {
  'use strict';

  // 1. No service worker (6.11): never register one, and unregister any that
  //    an earlier build installed. Errors are ignored.
  try {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(function (registrations) {
        registrations.forEach(function (registration) {
          registration.unregister().catch(function () {});
        });
      }).catch(function () {});
    }
  } catch (e) {
    // Ignored: some browsers throw in private mode.
  }

  // 2. Renderer (6.10): ?renderer=skwasm|canvaskit|default, remembered in
  //    localStorage['noteapp.renderer']. skwasm only when this build has a
  //    dart2wasm variant; otherwise CanvasKit.
  var STORAGE_KEY = 'noteapp.renderer';
  var requested = null;
  try {
    requested = new URLSearchParams(window.location.search).get('renderer');
  } catch (e) {
    requested = null;
  }
  try {
    if (requested === 'default') {
      window.localStorage.removeItem(STORAGE_KEY);
      requested = null;
    } else if (requested === 'skwasm' || requested === 'canvaskit') {
      window.localStorage.setItem(STORAGE_KEY, requested);
    } else {
      requested = window.localStorage.getItem(STORAGE_KEY);
    }
  } catch (e) {
    // localStorage unavailable: use the URL value only.
  }
  var builds = (_flutter.buildConfig && _flutter.buildConfig.builds) || [];
  var hasWasmBuild = builds.some(function (build) {
    return build.compileTarget === 'dart2wasm';
  });
  var config = requested === 'skwasm' && hasWasmBuild
    ? { renderer: 'skwasm', wasmAllowList: { blink: true, gecko: true, webkit: true } }
    : { renderer: 'canvaskit' };

  function setStatus(text) {
    var status = document.getElementById('app-loader-status');
    if (status) status.textContent = text;
  }

  // 3. Load. Errors reach index.html's error / unhandledrejection handlers.
  _flutter.loader.load({
    config: config,
    onEntrypointLoaded: function (engineInitializer) {
      setStatus('엔진 준비 중…');
      return engineInitializer.initializeEngine().then(function (appRunner) {
        setStatus('앱 시작 중…');
        return appRunner.runApp();
      });
    },
  });
})();
