// The image import flow (m5-7/06-pdf 6.12.1, 4.2.4 — 8.2 T35b; PDF-M10, contract 7.2.10 v2.1):
// the picker opens in the same synchronous run as the call (before the returned Future is
// awaited), no ProviderScope → fails before picking, cancel → null without a snack bar, success
// → AssetStore.put(type: image, mime) + ImportedImage size and the 6.12.5 file name, the editor
// gone after the pick → no snack bar / sheet / put, every 6.16 error text, the preparing sheet
// only after the pick and only past 400 ms (enableDrag false), and the real image_picker port on
// FakeImagePickerPlatform (photos / files → gallery, camera → camera, no camera → its text).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/image/image_codec.dart';
import 'package:media_io/src/image/image_codec_io.dart';
import 'package:media_io/src/image/image_import.dart';
import 'package:media_io/src/image/image_normalizer.dart';
import 'package:media_io/src/image/image_picker_port.dart';
import 'package:media_io/src/ui/strings_ko.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/ipad.dart';

/// A picker that records when it was asked and answers what the test says.
final class FakePickerPort implements ImagePickerPort {
  final List<core.ImageImportSource> calls = [];

  /// When set, pick() waits for it.
  Completer<PickedImage?>? gate;
  PickedImage? next;
  Object? error;

  @override
  Future<PickedImage?> pick(core.ImageImportSource source) {
    calls.add(source);
    if (gate case final g?) return g.future;
    if (error case final e?) return Future.error(e);
    return Future.value(next);
  }
}

Uint8List pngOf(int w, int h) =>
    Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

Uint8List jpegOf(int w, int h) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

/// The real rules on the calling isolate (no compute in fake time).
Future<NormalizedImage> realNormalize(Uint8List bytes) =>
    const ImageNormalizer(codec: IoImageCodec(useIsolate: false))
        .normalize(bytes);

final class ImportWorld {
  ImportWorld()
    : store = core_testing.createFakeNoteStore(
        clock: FakeAsync().getClock(DateTime(2026, 11, 6, 9, 5, 7)),
      );

  final core.NoteStore store;
  final FakePickerPort picker = FakePickerPort();
  late BuildContext context;

  Widget app({bool withScope = true}) {
    final body = MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    return withScope
        ? ProviderScope(
            overrides: [core.noteStoreProvider.overrideWithValue(store)],
            child: body,
          )
        : body;
  }

  Future<void> pump(WidgetTester tester, {bool withScope = true}) =>
      pumpOnIpad(tester, app(withScope: withScope));

  Future<core.ImportedImage?> import(
    core.ImageImportSource source, {
    Future<NormalizedImage> Function(Uint8List)? normalize,
  }) => importImageWith(
    context,
    source,
    picker: picker,
    normalize: normalize ?? realNormalize,
  );

  Future<List<core.Asset>> assets() => store.assets.listAssets();
}

/// Lets a Future of the import finish in widget-test fake time.
Future<T> settled<T>(WidgetTester tester, Future<T> future) async {
  T? value;
  Object? error;
  StackTrace? stack;
  var done = false;
  unawaited(
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace st) {
        error = e;
        stack = st;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 20 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(done, isTrue, reason: 'the import did not finish');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
}

String? snackText(WidgetTester tester) {
  final f = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Text),
  );
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f.first).data;
}

void main() {
  group('synchronous start (7.2.10 v2.1)', () {
    testWidgets('pick runs before the returned Future is awaited', (
      tester,
    ) async {
      final w = ImportWorld();
      await w.pump(tester);
      w.picker.gate = Completer();
      final result = w.import(core.ImageImportSource.clipboard);
      // nothing awaited yet: the picker / clipboard read is already open
      expect(w.picker.calls, [core.ImageImportSource.clipboard]);
      w.picker.gate!.complete(PickedImage(pngOf(40, 30)));
      final image = await settled(tester, result);
      expect(image, isNotNull);
    });

    testWidgets('no ProviderScope → it fails before picking', (tester) async {
      final w = ImportWorld();
      await w.pump(tester, withScope: false);
      final result = w.import(core.ImageImportSource.photos);
      expect(w.picker.calls, isEmpty);
      await expectLater(result, throwsA(anything));
    });
  });

  group('results (4.2.4)', () {
    testWidgets('cancel → null, no snack bar, nothing stored', (tester) async {
      final w = ImportWorld();
      await w.pump(tester);
      expect(
        await settled(tester, w.import(core.ImageImportSource.photos)),
        isNull,
      );
      await tester.pump();
      expect(snackText(tester), isNull);
      expect(await settled(tester, w.assets()), isEmpty);
    });

    testWidgets(
      'success → put(type: image, image/png) and the pixel size; the picked name keeps its stem',
      (tester) async {
        final w = ImportWorld();
        await w.pump(tester);
        final png = pngOf(300, 200);
        w.picker.next = PickedImage(png, name: 'board.PNG');
        final image = await settled(
          tester,
          w.import(core.ImageImportSource.files),
        );
        expect(image!.pixelWidth, 300);
        expect(image.pixelHeight, 200);
        expect(image.asset.type, core.AssetType.image);
        expect(image.asset.mimeType, 'image/png');
        expect(image.asset.fileName, 'board.png');
        expect(
          await settled(tester, w.store.assets.readBytes(image.asset.id)),
          png,
        );
        await tester.pump();
        expect(snackText(tester), isNull);
      },
    );

    testWidgets(
      'camera / clipboard (no name) → 이미지-<yyyyMMdd-HHmmss>.jpg; a HEIC name becomes .jpg',
      (tester) async {
        final w = ImportWorld();
        await w.pump(tester);
        w.picker.next = PickedImage(jpegOf(64, 48));
        final shot = await settled(
          tester,
          w.import(core.ImageImportSource.camera),
        );
        expect(shot!.asset.mimeType, 'image/jpeg');
        expect(shot.asset.fileName, '이미지-20261106-090507.jpg');

        // other bytes (the asset store keeps one asset per content)
        w.picker.next = PickedImage(jpegOf(64, 49), name: 'IMG_0001.HEIC');
        final heic = await settled(
          tester,
          w.import(core.ImageImportSource.photos),
        );
        expect(heic!.asset.fileName, 'IMG_0001.jpg');
      },
    );

    testWidgets(
      'the editor goes away after the pick → no snack bar, no sheet, no put',
      (tester) async {
        final w = ImportWorld();
        await w.pump(tester);
        w.picker.gate = Completer();
        final result = w.import(core.ImageImportSource.photos);
        await pumpOnIpad(
          tester,
          ProviderScope(
            overrides: [core.noteStoreProvider.overrideWithValue(w.store)],
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        w.picker.gate!.complete(PickedImage(pngOf(40, 30)));
        expect(await settled(tester, result), isNull);
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(await settled(tester, w.assets()), isEmpty);
      },
    );

    testWidgets(
      'the editor goes away during the normalization → nothing stored',
      (tester) async {
        final w = ImportWorld();
        await w.pump(tester);
        w.picker.next = PickedImage(pngOf(40, 30));
        final gate = Completer<NormalizedImage>();
        final result = w.import(
          core.ImageImportSource.photos,
          normalize: (_) => gate.future,
        );
        await tester.pump();
        await pumpOnIpad(
          tester,
          ProviderScope(
            overrides: [core.noteStoreProvider.overrideWithValue(w.store)],
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        gate.complete(await realNormalize(pngOf(40, 30)));
        expect(await settled(tester, result), isNull);
        expect(await settled(tester, w.assets()), isEmpty);
      },
    );
  });

  group('error texts (6.16)', () {
    const pickErrors = {
      MediaErrorCode.cameraUnavailable: '카메라를 쓸 수 없어요',
      MediaErrorCode.clipboardEmpty: '클립보드에 이미지가 없어요',
      MediaErrorCode.clipboardDenied: '붙여넣기를 허용한 뒤 다시 눌러 주세요',
      MediaErrorCode.decodeFailed: '이미지를 읽지 못했어요',
    };
    for (final MapEntry(key: code, value: text) in pickErrors.entries) {
      testWidgets('pick: ${code.name} → "$text", null', (tester) async {
        final w = ImportWorld();
        await w.pump(tester);
        w.picker.error = MediaIoException(code);
        expect(
          await settled(tester, w.import(core.ImageImportSource.camera)),
          isNull,
        );
        await tester.pump();
        expect(snackText(tester), text);
      });
    }

    const normalizeErrors = {
      MediaErrorCode.decodeFailed: '이미지를 읽지 못했어요',
      MediaErrorCode.unsupportedFormat: '이 형식의 이미지는 넣을 수 없어요',
      MediaErrorCode.tooLarge: '이미지가 너무 커서 넣을 수 없어요',
    };
    for (final MapEntry(key: code, value: text) in normalizeErrors.entries) {
      testWidgets('normalize: ${code.name} → "$text", nothing stored', (
        tester,
      ) async {
        final w = ImportWorld();
        await w.pump(tester);
        w.picker.next = PickedImage(pngOf(4, 4));
        expect(
          await settled(
            tester,
            w.import(
              core.ImageImportSource.photos,
              normalize: (_) => Future.error(MediaIoException(code)),
            ),
          ),
          isNull,
        );
        await tester.pump();
        expect(snackText(tester), text);
        expect(await settled(tester, w.assets()), isEmpty);
      });
    }

    testWidgets(
      'the real rules: bytes that are no image → unsupported format',
      (tester) async {
        final w = ImportWorld();
        await w.pump(tester);
        w.picker.next = PickedImage(Uint8List.fromList(List.filled(64, 7)));
        expect(
          await settled(tester, w.import(core.ImageImportSource.photos)),
          isNull,
        );
        await tester.pump();
        expect(snackText(tester), '이 형식의 이미지는 넣을 수 없어요');
      },
    );

    testWidgets('put fails → "이미지를 저장하지 못했어요", reported, null', (tester) async {
      final w = ImportWorld();
      await w.pump(tester);
      w.picker.next = PickedImage(pngOf(4, 4));
      // CORE refuses a local image asset that is not JPEG / PNG (ArgumentError)
      final result = await settled(
        tester,
        w.import(
          core.ImageImportSource.photos,
          normalize: (b) async => NormalizedImage(
            bytes: b,
            mimeType: 'image/webp',
            width: 4,
            height: 4,
            path: NormalizePath.slow,
          ),
        ),
      );
      expect(result, isNull);
      expect(tester.takeException(), isArgumentError);
      await tester.pump();
      expect(snackText(tester), MediaStringsKo.imageSaveFailed);
    });

    test('importErrorText covers every import code', () {
      expect(
        importErrorText(MediaErrorCode.saveFailed),
        MediaStringsKo.imageSaveFailed,
      );
      expect(
        importErrorText(MediaErrorCode.engineFailed),
        MediaStringsKo.imageDecodeFailed,
        reason: 'anything else: the closest text',
      );
    });
  });

  group('the preparing sheet (6.12.1)', () {
    testWidgets(
      'only after the pick, only past 400 ms; enableDrag false; closed when done',
      (tester) async {
        final w = ImportWorld();
        await w.pump(tester);
        w.picker.gate = Completer();
        final normalized = Completer<NormalizedImage>();
        final result = w.import(
          core.ImageImportSource.photos,
          normalize: (_) => normalized.future,
        );
        // the picker is open for a long time: no sheet before the pick
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(BottomSheet), findsNothing);

        w.picker.gate!.complete(PickedImage(pngOf(40, 30)));
        await tester.pump(const Duration(milliseconds: 399));
        expect(find.byType(BottomSheet), findsNothing);
        await tester.pump(const Duration(milliseconds: 2));
        await tester.pump(
          const Duration(milliseconds: 300),
        ); // the sheet animates in
        expect(find.text(MediaStringsKo.imagePreparing), findsOneWidget);
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.enableDrag, isFalse);
        // not dismissible: a tap on the barrier keeps it
        await tester.tapAt(const Offset(10, 10));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(MediaStringsKo.imagePreparing), findsOneWidget);

        normalized.complete(await realNormalize(pngOf(40, 30)));
        final image = await settled(tester, result);
        expect(image, isNotNull);
        await tester.pumpAndSettle();
        expect(find.text(MediaStringsKo.imagePreparing), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
      },
    );

    testWidgets('a quick normalization shows no sheet', (tester) async {
      final w = ImportWorld();
      await w.pump(tester);
      w.picker.next = PickedImage(pngOf(40, 30));
      expect(
        await settled(tester, w.import(core.ImageImportSource.photos)),
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('the image_picker port on FakeImagePickerPlatform', () {
    late MediaFakePlatforms fakes;
    setUp(() => fakes = installFakeMediaPlatforms());
    tearDown(() => fakes.dispose());

    testWidgets(
      'importImageForNote: photos / files → gallery, camera → camera; the asset is stored',
      (tester) async {
        final w = ImportWorld();
        await w.pump(tester);
        fakes.picker
          ..enqueue(pngOf(120, 80), name: 'whiteboard.png')
          ..enqueue(pngOf(10, 10), name: 'a.png')
          ..enqueue(null);
        final first = await settled(
          tester,
          importImageForNote(w.context, core.ImageImportSource.photos),
        );
        expect(first!.pixelWidth, 120);
        expect(first.asset.fileName, 'whiteboard.png');
        await settled(
          tester,
          importImageForNote(w.context, core.ImageImportSource.files),
        );
        expect(
          await settled(
            tester,
            importImageForNote(w.context, core.ImageImportSource.camera),
          ),
          isNull,
        );
        expect(fakes.picker.sources, [
          ImageSource.gallery,
          ImageSource.gallery,
          ImageSource.camera,
        ]);
        expect(await settled(tester, w.assets()), hasLength(2));
      },
    );

    testWidgets('no camera (PlatformException) → "카메라를 쓸 수 없어요"', (
      tester,
    ) async {
      ImagePickerPlatform.instance = _NoCameraPicker();
      final w = ImportWorld();
      await w.pump(tester);
      expect(
        await settled(
          tester,
          importImageForNote(w.context, core.ImageImportSource.camera),
        ),
        isNull,
      );
      await tester.pump();
      expect(snackText(tester), '카메라를 쓸 수 없어요');
    });

    test(
      'another picker PlatformException is unexpected → it throws',
      () async {
        ImagePickerPlatform.instance = _NoCameraPicker(code: 'already_active');
        await expectLater(
          PluginImagePickerPort().pick(core.ImageImportSource.camera),
          throwsA(isA<PlatformException>()),
        );
      },
    );
  });
}

final class _NoCameraPicker extends ImagePickerPlatform {
  _NoCameraPicker({this.code = 'no_available_camera'});
  final String code;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => throw PlatformException(code: code);
}
