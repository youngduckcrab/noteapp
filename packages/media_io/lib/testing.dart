/// Test helpers of media_io (m5-7/06-pdf 4.3.2, contract 00-overview 7.6 — test/ only).
///
/// Web-safe entry point (Chrome tests import it for registerMediaWebPlugins); no
/// flutter_test. The web registration body and the dart:io hooks sit behind conditional
/// exports (src/testing_web_factory.dart, src/testing_vm_factory.dart).
///
/// ```text
/// // package:media_io/testing.dart (test/ only) — (v2.1, CP-PDF-6 + PDF review M-1)
/// // registerMediaWebPlugins() — Chrome tests call it (flutter test --platform chrome does not run
/// //   the plugin registrant).
/// // VM only (assert !kIsWeb): FakeRecordPlatform extends RecordPlatform, FakeJustAudioPlatform
/// //   extends JustAudioPlatform, FakeImagePickerPlatform extends ImagePickerPlatform — plain
/// //   `extends` (the token check passes); NO MockPlatformInterfaceMixin (@visibleForTesting → an
/// //   analysis error in lib/). installFakeMediaPlatforms({bool micPermission = true}) →
/// //   MediaFakePlatforms. For media_io's own service tests; the web recorder is MediaRecorder, so
/// //   these have no effect in Chrome — Chrome tests and the app smoke override CORE's audio ports
/// //   with FakeAudioRecorder / FakeAudioPlayback (INFRA: through module injection arguments).
/// ```
///
/// 2차 foundation step R2-B4 (PDF T30): registerMediaWebPlugins works; the three platform
/// fakes have their basic behaviour (src/testing/fake_platforms.dart).
library;

import 'package:flutter/foundation.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'src/testing/fake_platforms.dart';
import 'src/testing/test_hooks.dart';
import 'src/testing_vm_factory.dart';
import 'src/testing_web_factory.dart';

export 'src/testing/fake_platforms.dart'
    show FakeRecordPlatform, FakeJustAudioPlatform, FakeImagePickerPlatform;

/// Chrome: JustAudioPlugin.registerWith(webPluginRegistrar) + RecordPluginWeb.registerWith(…), once.
/// VM: does nothing. (flutter test --platform chrome does not run the plugin registrant — 조사 02 5.2.)
void registerMediaWebPlugins() => registerMediaWebPluginsImpl();

/// (CP-PDF-6, v2.1 VM only) Installs the three fakes plus media_io's internal hooks (a temp
/// directory instead of path_provider — testing_vm_native.dart, a no-op foreground service), so the
/// REAL mediaIoOverrides() services run in a VM test. assert(!kIsWeb) — on the web the recorder is
/// media_io's own MediaRecorder engine and these fakes would have no effect. dispose() restores the
/// previous instances and deletes the temp directory.
MediaFakePlatforms installFakeMediaPlatforms({bool micPermission = true}) {
  assert(!kIsWeb, mediaFakesVmOnlyMessage);
  final previous = (
    record: RecordPlatform.instance,
    player: JustAudioPlatform.instance,
    picker: ImagePickerPlatform.instance,
    directory: MediaTestHooks.directory,
    noForegroundService: MediaTestHooks.noForegroundService,
  );
  final record = FakeRecordPlatform.install(permission: micPermission);
  final player = FakeJustAudioPlatform.install();
  final picker = FakeImagePickerPlatform();
  ImagePickerPlatform.instance = picker;
  final directory = createMediaTestDirectory();
  MediaTestHooks.directory = directory?.path;
  MediaTestHooks.noForegroundService = true;
  return MediaFakePlatforms._(record, player, picker, directory?.path, () {
    RecordPlatform.instance = previous.record;
    JustAudioPlatform.instance = previous.player;
    ImagePickerPlatform.instance = previous.picker;
    MediaTestHooks.directory = previous.directory;
    MediaTestHooks.noForegroundService = previous.noForegroundService;
    directory?.delete();
  });
}

/// What installFakeMediaPlatforms installed. [dispose] is idempotent.
final class MediaFakePlatforms {
  MediaFakePlatforms._(
    this.record,
    this.player,
    this.picker,
    this.directory,
    this._restore,
  );

  final FakeRecordPlatform record;
  final FakeJustAudioPlatform player;
  final FakeImagePickerPlatform picker;
  void Function()? _restore;

  /// The temp directory media_io writes to while these fakes are installed (recordings, play
  /// cache); deleted by [dispose].
  final String? directory;

  /// Restores the previous platform instances and hooks and deletes the temp directory.
  void dispose() {
    final restore = _restore;
    _restore = null;
    restore?.call();
  }
}
