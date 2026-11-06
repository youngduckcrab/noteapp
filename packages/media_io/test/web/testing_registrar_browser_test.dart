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
import 'package:note_core/note_core.dart' as core;
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

  test('the barrel runs in the browser: initializeMediaIo, the two overrides (T37)', () async {
    await initializeMediaIo(); // the web MIME table is probed here (6.8.1)
    expect(mediaIoOverrides(), hasLength(2));
    // (T35b) the web image sources are real (web/image_codec_browser_test.dart)
    expect(
      supportedImageSources(),
      containsAll(const [
        core.ImageImportSource.photos,
        core.ImageImportSource.camera,
        core.ImageImportSource.files,
      ]),
    );
  });
}
