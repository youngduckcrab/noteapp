// package:media_io/testing.dart in Chrome (m5-7/06-pdf 4.3.2, 9.2, 8.1 T30):
// registerMediaWebPlugins registers the just_audio and record web plugins (the test binding
// runs no plugin registrant) and may be called again; the VM-only platform fakes assert in a
// browser (debug Chrome tests keep asserts on), with the message that points to CORE's
// FakeAudioRecorder / FakeAudioPlayback.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:just_audio_web/just_audio_web.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/testing.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/record_web.dart';

void main() {
  test('registerMediaWebPlugins: both web plugins, twice is fine', () {
    registerMediaWebPlugins();
    final player = JustAudioPlatform.instance;
    final recorder = RecordPlatform.instance;
    expect(player, isA<JustAudioPlugin>());
    expect(recorder, isA<RecordPluginWebWrapper>());
    registerMediaWebPlugins();
    expect(identical(JustAudioPlatform.instance, player), isTrue);
    expect(identical(RecordPlatform.instance, recorder), isTrue);
  });

  test('the platform fakes are VM-only (AssertionError in Chrome)', () {
    Matcher vmOnly() => throwsA(
      isA<AssertionError>().having(
        (e) => '${e.message}',
        'message',
        contains('FakeAudioRecorder / FakeAudioPlayback'),
      ),
    );
    expect(installFakeMediaPlatforms, vmOnly());
    expect(FakeRecordPlatform.new, vmOnly());
    expect(FakeJustAudioPlatform.new, vmOnly());
    expect(FakeImagePickerPlatform.new, vmOnly());
  });

  test('the barrel runs in the browser: R2-B4 bodies', () async {
    await initializeMediaIo();
    expect(mediaIoOverrides(), isEmpty);
    expect(supportedImageSources(), isEmpty);
  });
}
