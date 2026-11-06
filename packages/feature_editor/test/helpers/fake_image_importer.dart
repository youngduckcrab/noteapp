// test/helpers/fake_image_importer.dart — m5-7/04-editor 5.5, 6.12.2, 8.2
// E2-00.
//
// A fake for the image slot (editorImageImporterProvider). `pick` records
// each call with the moment it ran: [onPick] runs synchronously inside the
// call, before the first await, so a test can check that the editor called
// pick while its menu / sheet was still open (6.12.2 step 1, review S-6).
// By default pick puts a 1×1 PNG into the store's AssetStore
// (type: image) and returns an ImportedImage for it with
// [pixelWidth] × [pixelHeight].
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:feature_editor/feature_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart' as core;

/// A valid 1×1 PNG (transparent pixel).
final Uint8List kOnePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// One recorded pick call.
final class FakePickCall {
  FakePickCall(this.context, this.source, this.index);
  final BuildContext context;
  final core.ImageImportSource source;

  /// 0, 1, 2… in call order.
  final int index;

  /// Whether [context] was mounted when pick was called.
  late final bool contextMounted = context.mounted;
}

class FakeImageImporter {
  FakeImageImporter({
    required this.store,
    this.sources = const {
      core.ImageImportSource.photos,
      core.ImageImportSource.files,
    },
    this.pixelWidth = 400,
    this.pixelHeight = 300,
  });

  final core.NoteStore store;
  final Set<core.ImageImportSource> sources;
  int pixelWidth, pixelHeight;

  /// Runs synchronously inside every pick call (before any await).
  void Function(FakePickCall call)? onPick;

  /// The next call returns this instead of putting a new asset.
  core.ImportedImage? next;

  /// The next call returns null (the user cancelled).
  bool cancelNext = false;

  /// The next call fails: synchronously (throws from pick itself) when
  /// [throwSynchronously], else through the returned Future.
  Object? throwNext;
  bool throwSynchronously = false;

  /// When set, the next call waits for this completer before it finishes
  /// (a picker that is still open).
  Completer<void>? holdNext;

  final List<FakePickCall> calls = [];

  /// The asset ids this fake put into the store, in call order.
  final List<core.AssetId> putAssetIds = [];

  /// The slot value to override editorImageImporterProvider with. The same
  /// instance is returned every time, so provider values compare equal.
  late final EditorImageImporter importer = EditorImageImporter(
    sources: sources,
    pick: pick,
  );

  Future<core.ImportedImage?> pick(
    BuildContext context,
    core.ImageImportSource source,
  ) {
    final call = FakePickCall(context, source, calls.length);
    call.contextMounted; // read now, not later
    calls.add(call);
    onPick?.call(call);
    final error = throwNext;
    if (error != null) {
      throwNext = null;
      if (throwSynchronously) {
        throwSynchronously = false;
        Error.throwWithStackTrace(error, StackTrace.current);
      }
      return Future.error(error);
    }
    return _finish();
  }

  Future<core.ImportedImage?> _finish() async {
    final hold = holdNext;
    holdNext = null;
    if (hold != null) await hold.future;
    if (cancelNext) {
      cancelNext = false;
      return null;
    }
    final given = next;
    if (given != null) {
      next = null;
      return given;
    }
    final asset = await store.assets.put(
      kOnePixelPng,
      type: core.AssetType.image,
      mimeType: 'image/png',
      fileName: 'fake-${calls.length}.png',
    );
    putAssetIds.add(asset.id);
    return core.ImportedImage(
      asset: asset,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
  }
}
