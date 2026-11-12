// The on-device math engine's providers (ondevice/on_device_providers.dart)
// and mathRecognizerProvider's choice (providers.dart): manual (today's
// behaviour) until the model is ready AND recog.mathOnDevice is on, then
// the on-device engine; back to manual when the switch goes off or the
// model is deleted; recognitionOverrides() still has exactly 3 overrides;
// the web / desktops have no manager (unsupported state); the manager is
// disposed with the container.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/ondevice/math_model_manager.dart';
import 'package:ink_recognition/src/ondevice/on_device_platform_native.dart'
    as native;
import 'package:ink_recognition/src/ondevice/on_device_platform_stub.dart'
    as stub;
import 'package:ink_recognition/src/ondevice/on_device_providers.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/math_model_fakes.dart';

final class _FakeOnDevice implements MathRecognizer {
  _FakeOnDevice(this.install);
  final MathModelInstall install;

  @override
  String get engineId => 'fake-on-device';
  @override
  bool get isAvailable => true;
  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) async =>
      const MathResult(
        latex: 'x',
        engineId: 'fake-on-device',
        latency: Duration.zero,
      );
}

void main() {
  test(
    'manual until ready + switched on; off or deleted → manual again',
    () async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final storage = MemoryModelStorage();
      final manager = MathModelManager(
        storage: storage,
        createClient: FakeModelServer().client,
        manifest: fakeManifest,
      );
      final made = <MathModelInstall>[];
      final container = ProviderContainer(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          ...recognitionOverrides(),
          mathModelManagerProvider.overrideWithValue(manager),
          onDeviceMathRecognizerFactoryProvider.overrideWithValue((install) {
            made.add(install);
            return _FakeOnDevice(install);
          }),
        ],
      );
      addTearDown(container.dispose);
      final seen = <MathRecognizer>[];
      container.listen(
        mathRecognizerProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await pumpEventQueue();
        }
      }

      expect(
        container.read(mathRecognizerProvider),
        isA<ManualOnlyMathRecognizer>(),
      );

      // switched on, model not there yet → still manual
      await store.settings.set(RecognitionSettingsKeys.mathOnDevice, true);
      await settle();
      expect(
        container.read(mathRecognizerProvider),
        isA<ManualOnlyMathRecognizer>(),
      );

      await manager.download();
      await settle();
      expect(container.read(mathModelStateProvider), isA<MathModelReady>());
      expect(container.read(mathRecognizerProvider), isA<_FakeOnDevice>());
      expect(made, hasLength(1));

      // switched off → manual (the files stay)
      await store.settings.set(RecognitionSettingsKeys.mathOnDevice, false);
      await settle();
      expect(
        container.read(mathRecognizerProvider),
        isA<ManualOnlyMathRecognizer>(),
      );
      expect(container.read(mathModelStateProvider), isA<MathModelReady>());

      // on again → the engine; deleted → manual
      await store.settings.set(RecognitionSettingsKeys.mathOnDevice, true);
      await settle();
      expect(container.read(mathRecognizerProvider), isA<_FakeOnDevice>());
      await manager.delete();
      await settle();
      expect(
        container.read(mathModelStateProvider),
        const MathModelNotInstalled(),
      );
      expect(
        container.read(mathRecognizerProvider),
        isA<ManualOnlyMathRecognizer>(),
      );
      expect(seen.whereType<_FakeOnDevice>(), isNotEmpty);
    },
  );

  test('download progress does not rebuild the math engine', () async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final manager = MathModelManager(
      storage: MemoryModelStorage(),
      createClient: FakeModelServer(chunk: 4096).client,
      manifest: fakeManifest,
    );
    final container = ProviderContainer(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        ...recognitionOverrides(),
        mathModelManagerProvider.overrideWithValue(manager),
      ],
    );
    addTearDown(container.dispose);
    var changes = 0;
    container.listen(mathRecognizerProvider, (_, _) => changes++);
    final states = <MathModelState>[];
    container.listen(mathModelStateProvider, (_, s) => states.add(s));
    await manager.download();
    await pumpEventQueue();
    expect(states.whereType<MathModelDownloading>().length, greaterThan(3));
    expect(changes, 0, reason: 'recog.mathOnDevice is off');
  });

  test('recognitionOverrides() still has exactly the 3 overrides', () {
    expect(recognitionOverrides(), hasLength(3));
  });

  test('platform side: the web stub has no manager; desktops neither; '
      'Android / iOS get one', () {
    expect(stub.createPlatformMathModelManager(), isNull);
    expect(
      stub.createOnDeviceMathRecognizer(const MathModelInstall({})),
      isA<ManualOnlyMathRecognizer>(),
    );
    for (final (platform, has) in [
      (TargetPlatform.android, true),
      (TargetPlatform.iOS, true),
      (TargetPlatform.macOS, false),
      (TargetPlatform.linux, false),
      (TargetPlatform.windows, false),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      final m = native.createPlatformMathModelManager();
      expect(m != null, has, reason: '$platform');
      m?.dispose();
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('no manager → MathModelUnsupported, no engine', () {
    final container = ProviderContainer.test(
      overrides: [mathModelManagerProvider.overrideWithValue(null)],
    );
    expect(
      container.read(mathModelStateProvider),
      const MathModelUnsupported(),
    );
    expect(container.read(onDeviceMathRecognizerProvider), isNull);
  });

  test(
    'the manager is disposed with the container (a download stops)',
    () async {
      final server = FakeModelServer()
        ..hold = Completer<void>()
        ..holdFile = 'encoder_model.int8pc.onnx';
      final manager = MathModelManager(
        storage: MemoryModelStorage(),
        createClient: server.client,
        manifest: fakeManifest,
      );
      final container = ProviderContainer(
        overrides: [
          mathModelManagerProvider.overrideWith((ref) {
            ref.onDispose(manager.dispose);
            return manager;
          }),
        ],
      );
      expect(container.read(mathModelManagerProvider), same(manager));
      final run = manager.download();
      await pumpEventQueue();
      container.dispose();
      await run; // cancelled by dispose
      server.hold!.complete();
    },
  );
}
