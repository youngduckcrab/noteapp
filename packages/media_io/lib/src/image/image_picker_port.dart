// lib/src/image/image_picker_port.dart — the picker the import flow drives (m5-7/06-pdf 6.12.1,
// 6.12.4): image_picker for photos / files / camera, the web clipboard read for clipboard. The
// test seam of importImageForNote (unit/image_import_test.dart). Internal; the only file that
// imports package:image_picker (3.5 I-4).
//
// pick() OPENS the picker before it returns (7.2.10 v2.1 — the user's tap): ImagePicker.pickImage
// goes synchronously to image_picker_for_web's input.click() on the web, the clipboard port calls
// navigator.clipboard.read() at once; the returned Future is awaited after that.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import 'image_codec.dart';
import 'image_codec_factory.dart';

abstract interface class ImagePickerPort {
  /// Opens the picker for [source] now and completes with what was picked, or null when the
  /// user cancelled. Throws MediaIoException (cameraUnavailable, clipboardEmpty, clipboardDenied,
  /// decodeFailed when the picked file cannot be read).
  Future<PickedImage?> pick(core.ImageImportSource source);
}

/// image_picker's PlatformException codes that mean 'no camera to use' (Android
/// ImagePickerDelegate, iOS ImagePickerPlugin).
const Set<String> cameraUnavailableCodes = {
  'no_available_camera',
  'camera_access_denied',
  'camera_access_restricted',
};

final class PluginImagePickerPort implements ImagePickerPort {
  PluginImagePickerPort({
    ImagePicker? picker,
    Future<PickedImage?> Function()? clipboard,
  }) : _picker = picker ?? ImagePicker(),
       _clipboard = clipboard ?? readClipboardImage;

  final ImagePicker _picker;
  final Future<PickedImage?> Function() _clipboard;

  @override
  Future<PickedImage?> pick(core.ImageImportSource source) => switch (source) {
    core.ImageImportSource.clipboard => _clipboard(),
    core.ImageImportSource.photos ||
    core.ImageImportSource.files => _fromPicker(ImageSource.gallery),
    core.ImageImportSource.camera => _fromPicker(ImageSource.camera),
  };

  Future<PickedImage?> _fromPicker(ImageSource source) {
    // 6.12.3: native pickers shrink first (HEIC → JPEG); the web gets no maxWidth so
    // image_picker_for_web's canvas and the normalizer do not both scale.
    final Future<XFile?> picked = kIsWeb
        ? _picker.pickImage(source: source, requestFullMetadata: false)
        : _picker.pickImage(
            source: source,
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 90,
            requestFullMetadata: false,
          );
    return _read(picked, camera: source == ImageSource.camera);
  }

  static Future<PickedImage?> _read(
    Future<XFile?> picked, {
    required bool camera,
  }) async {
    final XFile? file;
    try {
      file = await picked;
    } on PlatformException catch (e) {
      if (camera && cameraUnavailableCodes.contains(e.code)) {
        throw MediaIoException(
          MediaErrorCode.cameraUnavailable,
          detail: e.code,
        );
      }
      rethrow;
    }
    if (file == null) return null;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object catch (e) {
      throw MediaIoException(
        MediaErrorCode.decodeFailed,
        detail: 'picked file not readable',
        cause: e,
      );
    }
    final name = file.name;
    return PickedImage(bytes, name: name.isEmpty ? null : name);
  }
}
