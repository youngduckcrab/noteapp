// settings › 인식 › '기기에서 수식 인식' (settings/on_device_math_tile.dart):
// off → the size note, nothing downloaded; on → recog.mathOnDevice = true and
// the download with its progress bar and [취소]; ready → '준비됨 · 약 N MB'
// [지우기] (files removed, switch off); failed → the reason and [다시];
// cancel → back to not installed; the engine row says '기기 안 엔진' while
// the on-device engine is in use; no manager (web, desktops) → no tile.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/l10n/recognition_strings.dart';
import 'package:ink_recognition/src/ondevice/math_model_manager.dart';
import 'package:ink_recognition/src/ondevice/math_model_manifest.dart';
import 'package:ink_recognition/src/ondevice/on_device_providers.dart';
import 'package:ink_recognition/src/settings/on_device_math_tile.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/src/settings/recognition_settings_section.dart'
    show RecognitionSettingsUiKeys;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/math_model_fakes.dart';
import '../support/recognition_test_scope.dart';

Future<core.NoteStore> _pump(
  WidgetTester tester, {
  required MathModelManager? manager,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = kIpadPortrait;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createFixedClockStore();
  addTearDown(store.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        mathModelManagerProvider.overrideWithValue(manager),
        ...overrides,
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(width: 720, child: RecognitionSettingsSection()),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return store;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

/// Pumps (fake time, 10 ms a frame) until [done] — the manager's download
/// runs in the test's zone.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'condition not reached');
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

Future<core.SettingsSnapshot> _read(
  WidgetTester tester,
  core.NoteStore store,
) async {
  final c = ProviderScope.containerOf(
    tester.element(find.byType(RecognitionSettingsSection)),
  );
  return c.read(core.settingsSnapshotProvider).requireValue;
}

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(OnDeviceMathKeys.status)).data!;

bool _on(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byKey(OnDeviceMathKeys.toggle)).value;

MathModelManager _manager(FakeModelServer server, MemoryModelStorage storage) =>
    MathModelManager(
      storage: storage,
      createClient: server.client,
      manifest: fakeManifest,
    );

void main() {
  final mb = (fakeManifest.totalBytes / 1000000).round();

  testWidgets('off: the size note, nothing downloaded', (tester) async {
    final server = FakeModelServer();
    final manager = _manager(server, MemoryModelStorage());
    await _pump(tester, manager: manager);
    expect(find.text(RecognitionStrings.onDeviceMathTitle), findsOneWidget);
    expect(find.text(RecognitionStrings.onDeviceMathBody), findsOneWidget);
    expect(_on(tester), isFalse);
    expect(_status(tester), RecognitionStrings.onDeviceMathOffNote(mb));
    expect(find.byKey(OnDeviceMathKeys.download), findsNothing);
    expect(server.requests, isEmpty);
    // the real manifest's size is the advertised ≈ 32 MB
    expect(
      RecognitionStrings.onDeviceMathOffNote(
        (kMathModelManifest.totalBytes / 1000000).round(),
      ),
      contains('약 32MB'),
    );
  });

  testWidgets('on: saved, the download runs with a progress bar and '
      '[취소]; ready → 준비됨 [지우기]; 지우기 → files gone, switch off', (tester) async {
    final storage = MemoryModelStorage();
    final server = FakeModelServer()
      ..hold = Completer<void>()
      ..holdFile = kMathModelEncoderFile;
    final manager = _manager(server, storage);
    final store = await _pump(tester, manager: manager);

    await _tap(tester, find.byKey(OnDeviceMathKeys.toggle));
    await _settle(tester);
    expect(
      (await _read(tester, store)).get(RecognitionSettingsKeys.mathOnDevice),
      isTrue,
    );
    expect(_on(tester), isTrue);
    expect(manager.state.value, isA<MathModelDownloading>());
    expect(find.byKey(OnDeviceMathKeys.progress), findsOneWidget);
    expect(find.byKey(OnDeviceMathKeys.cancel), findsOneWidget);
    expect(_status(tester), startsWith('모델 받는 중…'));

    server.hold!.complete();
    await _until(tester, () => manager.state.value is! MathModelDownloading);
    expect(manager.state.value, isA<MathModelReady>());
    expect(_status(tester), RecognitionStrings.onDeviceMathReady(mb));
    expect(find.byKey(OnDeviceMathKeys.progress), findsNothing);
    expect(find.byKey(OnDeviceMathKeys.delete), findsOneWidget);

    await _tap(tester, find.byKey(OnDeviceMathKeys.delete));
    await _settle(tester);
    expect(manager.state.value, const MathModelNotInstalled());
    expect(storage.files, isEmpty);
    expect(_on(tester), isFalse);
  });

  testWidgets('[취소] stops the download → not installed; [받기] starts it '
      'again while the switch is on', (tester) async {
    final server = FakeModelServer()
      ..hold = Completer<void>()
      ..holdFile = kMathModelEncoderFile;
    final manager = _manager(server, MemoryModelStorage());
    await _pump(tester, manager: manager);
    await _tap(tester, find.byKey(OnDeviceMathKeys.toggle));
    await _settle(tester);
    await _tap(tester, find.byKey(OnDeviceMathKeys.cancel));
    await _settle(tester);
    expect(manager.state.value, const MathModelNotInstalled());
    expect(_status(tester), RecognitionStrings.onDeviceMathNotInstalled);
    expect(find.byKey(OnDeviceMathKeys.download), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(OnDeviceMathKeys.download),
        matching: find.text(RecognitionStrings.download),
      ),
      findsOneWidget,
    );
    server.hold!.complete();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('failed: the reason in the error colour and [다시]; [다시] '
      'downloads again', (tester) async {
    final storage = MemoryModelStorage();
    var fail = true;
    final good = FakeModelServer();
    final bad = FakeModelServer(failWith: http.ClientException('offline'));
    final manager = MathModelManager(
      storage: storage,
      createClient: () => fail ? bad.client() : good.client(),
      manifest: fakeManifest,
    );
    await _pump(tester, manager: manager);
    await _tap(tester, find.byKey(OnDeviceMathKeys.toggle));
    await _settle(tester);
    expect(
      manager.state.value,
      const MathModelFailed(MathModelFailure.offline),
    );
    expect(_status(tester), RecognitionStrings.onDeviceMathFailedOffline);
    final text = tester.widget<Text>(find.byKey(OnDeviceMathKeys.status));
    final theme = Theme.of(tester.element(find.byKey(OnDeviceMathKeys.status)));
    expect(text.style?.color, theme.colorScheme.error);
    expect(
      find.descendant(
        of: find.byKey(OnDeviceMathKeys.download),
        matching: find.text(RecognitionStrings.retry),
      ),
      findsOneWidget,
    );
    fail = false;
    await _tap(tester, find.byKey(OnDeviceMathKeys.download));
    await _until(tester, () => manager.state.value is MathModelReady);
    expect(_status(tester), RecognitionStrings.onDeviceMathReady(mb));
  });

  testWidgets('the engine row says 기기 안 엔진 while the on-device engine is '
      'in use', (tester) async {
    final storage = MemoryModelStorage();
    final manager = _manager(FakeModelServer(), storage);
    await tester.runAsync(manager.download);
    expect(manager.state.value, isA<MathModelReady>());
    final store = await _pump(
      tester,
      manager: manager,
      overrides: [
        ...recognitionOverrides(),
        onDeviceMathRecognizerFactoryProvider.overrideWithValue(
          (install) => _StubEngine(),
        ),
      ],
    );
    expect(
      find.descendant(
        of: find.byKey(RecognitionSettingsUiKeys.mathEngine),
        matching: find.text(RecognitionStrings.mathEngineManual),
      ),
      findsOneWidget,
    );
    unawaited(store.settings.set(RecognitionSettingsKeys.mathOnDevice, true));
    await _settle(tester);
    expect(
      find.descendant(
        of: find.byKey(RecognitionSettingsUiKeys.mathEngine),
        matching: find.text(RecognitionStrings.mathEngineOnDevice),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no manager (web, desktops) → no tile', (tester) async {
    await _pump(tester, manager: null);
    expect(find.byKey(OnDeviceMathKeys.toggle), findsNothing);
    expect(find.text(RecognitionStrings.onDeviceMathTitle), findsNothing);
  });
}

final class _StubEngine implements MathRecognizer {
  @override
  String get engineId => 'pix2text-mfr/1.5-int8pc';
  @override
  bool get isAvailable => true;
  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) =>
      throw UnimplementedError();
}
