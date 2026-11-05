// Web: iOS Safari sets navigator.standalone; other browsers report the
// display-mode media feature (6.10.1).
import 'dart:js_interop';

import 'package:web/web.dart' as web;

extension type _StandaloneNavigator._(JSObject _) implements JSObject {
  external JSBoolean? get standalone;
}

/// Whether the page runs as a web app added to the home screen
/// (`navigator.standalone` or `display-mode: standalone`).
bool isStandaloneDisplayMode() {
  final navigator = _StandaloneNavigator._(web.window.navigator);
  if (navigator.standalone?.toDart ?? false) return true;
  return web.window.matchMedia('(display-mode: standalone)').matches;
}
