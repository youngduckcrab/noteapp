// lib/src/image/image_import.dart — supportedImageSources, importImageForNote (contract
// 7.2.12, m5-7/06-pdf 4.2.4, 6.12).
//
// importImageForNote (6.12.1, PDF-M10 — 7.2.10 v2.1 '자리 콜백 동기 시작'): EDITOR calls it
// synchronously inside onPressed with the editor body's context. Before the first await it takes
// the ProviderContainer (→ core.noteStoreProvider), the ScaffoldMessenger and the Navigator, and
// opens the picker (ImagePickerPort.pick — the web input.click() / navigator.clipboard.read()
// happen inside the tap). After every await, before any screen work, it checks context.mounted
// and uses only what it took (never `of(context)` again — use_build_context_synchronously).
// After the pick, a normalization longer than importProgressDelay (400 ms) shows the preparing
// sheet (material_ui showModalBottomSheet, isDismissible / enableDrag false — CP-PDF-11), closed
// through the taken navigator when done; never before the pick (a sheet before the picker would
// lose the user activation). Results: ImportedImage after AssetStore.put(type: image); null when
// cancelled, when the editor went away, or after a handled error shown as a snack bar (6.16);
// an unexpected error throws (EDITOR reports it — E-7). Works without initializeMediaIo
// (image import is outside FEATURE_MEDIA — D17).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import '../tuning.dart';
import '../ui/strings_ko.dart';
import 'image_codec.dart';
import 'image_codec_factory.dart';
import 'image_normalizer.dart';
import 'image_picker_port.dart';

/// EditorImageImporter parts (INFRA wraps them).
/// web: photos, camera, files (+ clipboard when navigator.clipboard.read exists)
///
/// (4.2.4) android / iOS: photos, camera; other platforms (desktop Flutter): none. Looks at the
/// platform only — callable before initializeMediaIo; FEATURE_MEDIA does not change it (D17).
Set<core.ImageImportSource> supportedImageSources() {
  if (kIsWeb) {
    return {
      core.ImageImportSource.photos,
      core.ImageImportSource.camera,
      core.ImageImportSource.files,
      if (clipboardImageReadable()) core.ImageImportSource.clipboard,
    };
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => const {
      core.ImageImportSource.photos,
      core.ImageImportSource.camera,
    },
    _ => const <core.ImageImportSource>{},
  };
}

/// Pick → decode → downscale to ImageImportLimits → re-encode (JPEG for photos, PNG when alpha)
/// → AssetStore.put(type: image). null = cancelled (or a handled error shown as a message).
/// (v2.1) Opens the system picker / clipboard read before its first await (7.2.10 rule); a long
/// normalization shows a preparing sheet (showModalBottomSheet — CP-PDF-11) after the pick.
/// Works without initializeMediaIo (image import is outside FEATURE_MEDIA — D17).
Future<core.ImportedImage?> importImageForNote(
  BuildContext context,
  core.ImageImportSource source,
) => importImageWith(
  context,
  source,
  picker: PluginImagePickerPort(),
  normalize: ImageNormalizer(codec: createPlatformImageCodec()).normalize,
);

/// importImageForNote with its parts given (unit/image_import_test.dart).
Future<core.ImportedImage?> importImageWith(
  BuildContext context,
  core.ImageImportSource source, {
  required ImagePickerPort picker,
  required Future<NormalizedImage> Function(Uint8List bytes) normalize,
  Duration progressDelay = MediaTuning.importProgressDelay,
}) async {
  // ── synchronous: before the first await (PDF-M10) ──
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  final store = container.read(core.noteStoreProvider);
  final picking = picker.pick(source);

  // ── from here on, awaits ──
  void tell(String text) {
    if (!context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  final PickedImage? picked;
  try {
    picked = await picking;
  } on MediaIoException catch (e) {
    tell(importErrorText(e.code));
    return null;
  }
  // cancelled / the editor went away
  if (picked == null || !context.mounted) return null;

  final sheet = _PreparingSheet();
  final timer = Timer(progressDelay, () {
    if (context.mounted) sheet.open(navigator);
  });
  try {
    final NormalizedImage n;
    try {
      n = await normalize(picked.bytes);
    } on MediaIoException catch (e) {
      tell(importErrorText(e.code));
      return null;
    }
    // nothing stored for an editor that is gone
    if (!context.mounted) return null;
    final core.Asset asset;
    try {
      asset = await store.assets.put(
        n.bytes,
        type: core.AssetType.image,
        mimeType: n.mimeType,
        fileName: importedImageFileName(
          picked.name,
          mimeType: n.mimeType,
          now: store.clock.now(),
        ),
      );
    } on Object catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'media_io',
          context: ErrorDescription('while storing an imported image'),
        ),
      );
      tell(MediaStringsKo.imageSaveFailed);
      return null;
    }
    return core.ImportedImage(
      asset: asset,
      pixelWidth: n.width,
      pixelHeight: n.height,
    );
  } finally {
    timer.cancel();
    sheet.close();
  }
}

/// The 6.16 snack bar text of an import error.
String importErrorText(MediaErrorCode code) => switch (code) {
  MediaErrorCode.unsupportedFormat => MediaStringsKo.imageUnsupportedFormat,
  MediaErrorCode.tooLarge => MediaStringsKo.imageTooLarge,
  MediaErrorCode.clipboardEmpty => MediaStringsKo.clipboardEmpty,
  MediaErrorCode.clipboardDenied => MediaStringsKo.clipboardDenied,
  MediaErrorCode.cameraUnavailable => MediaStringsKo.cameraUnavailable,
  MediaErrorCode.saveFailed => MediaStringsKo.imageSaveFailed,
  // decodeFailed and anything else: the closest text (6.16)
  _ => MediaStringsKo.imageDecodeFailed,
};

/// 6.12.5: the chosen file's name with the stored format's extension, else
/// `이미지-<yyyyMMdd-HHmmss>.jpg|png` (camera, clipboard) — [now] in local time.
String importedImageFileName(
  String? pickedName, {
  required String mimeType,
  required DateTime now,
}) {
  final ext = mimeType == 'image/png' ? 'png' : 'jpg';
  final name = pickedName?.trim() ?? '';
  if (name.isNotEmpty) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    if (stem.isNotEmpty) return '$stem.$ext';
  }
  return '${MediaStringsKo.imageFileStem(now.toLocal())}.$ext';
}

/// The '이미지를 준비하고 있어요…' sheet: opened by the timer, closed (removed — wherever it is
/// in the stack) when the import ends, even if it was not built yet.
final class _PreparingSheet {
  final ValueNotifier<bool> _done = ValueNotifier(false);
  bool _opened = false;

  void open(NavigatorState navigator) {
    if (_opened || _done.value || !navigator.mounted) return;
    _opened = true;
    unawaited(
      showModalBottomSheet<void>(
        context: navigator.context,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => _PreparingSheetBody(done: _done, navigator: navigator),
      ),
    );
  }

  void close() => _done.value = true;
}

final class _PreparingSheetBody extends StatefulWidget {
  const _PreparingSheetBody({required this.done, required this.navigator});

  final ValueListenable<bool> done;
  final NavigatorState navigator;

  @override
  State<_PreparingSheetBody> createState() => _PreparingSheetBodyState();
}

final class _PreparingSheetBodyState extends State<_PreparingSheetBody> {
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    widget.done.addListener(_onDone);
    if (widget.done.value) _onDone();
  }

  void _onDone() {
    if (_removed) return;
    _removed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = mounted ? ModalRoute.of(context) : null;
      if (route != null && route.isActive && widget.navigator.mounted) {
        widget.navigator.removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    widget.done.removeListener(_onDone);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SafeArea(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: 16),
          Expanded(child: Text(MediaStringsKo.imagePreparing)),
        ],
      ),
    ),
  );
}
