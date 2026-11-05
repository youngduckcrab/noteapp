// Standalone (home screen) web app detection for WebSignInMode.auto (6.10.1). Conditional
// export (contract 7.4.3): package:web only in display_mode_browser.dart.
export 'display_mode_stub.dart'
    if (dart.library.js_interop) 'display_mode_browser.dart';
