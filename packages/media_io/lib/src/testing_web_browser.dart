// lib/src/testing_web_browser.dart — testing_web_factory.dart in the browser. The test
// binding of `flutter test --platform chrome` does not run the generated web plugin
// registrant (조사 02 5.2), so Chrome tests register media_io's two web plugins themselves.
// record_web is registered for completeness only — media_io's web recorder is its own
// MediaRecorder engine (D13); just_audio_web is the web player.
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:just_audio_web/just_audio_web.dart';
import 'package:record_web/record_web.dart';

bool _registered = false;

/// JustAudioPlugin.registerWith(webPluginRegistrar) + RecordPluginWeb.registerWith(…), once.
void registerMediaWebPluginsImpl() {
  if (_registered) return;
  _registered = true;
  JustAudioPlugin.registerWith(webPluginRegistrar);
  RecordPluginWeb.registerWith(webPluginRegistrar);
}
