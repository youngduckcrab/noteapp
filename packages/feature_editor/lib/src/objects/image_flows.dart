// lib/src/objects/image_flows.dart — m5-7/04-editor 6.12 (image insert, image
// paste, image page — E2-12), 4.3.1 (the slot callback rules).
//
// Every image source the editor offers — the insert menu '이미지 › 출처', the
// context menu '이미지 붙여넣기', ⌘V with an empty app clipboard and the
// add-page sheet '이미지' row — runs here, inside the press (the button's
// onPressed / the key event):
//   ① ExtensionRunner.run starts importer.pick(bodyContext, source)
//      SYNCHRONOUSLY (a browser file input / navigator.clipboard.read only
//      opens inside the user activation), then [close] closes the menu or
//      sheet, then the Future is awaited;
//   ② one at a time: all of them share [runId], so a press while a picker
//      is open is ignored (the items are disabled — runningIds);
//   ③ null → nothing (cancelled); an exception → reported + '이미지를 넣지
//      못했어요' (E-7); the note screen closed meanwhile → dropped (6.21);
//   ④ the image → EditorCommands.insertImage / insertImagePage (one step).
import 'dart:async';
import 'dart:ui' show Offset, VoidCallback;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../commands/editor_commands.dart';
import '../commands/extension_runner.dart';
import '../di/editor_image_importer.dart';
import '../scope/editor_scope.dart';
import '../state/popup.dart';
import '../tools/selection.dart';
import '../ui/editor_strings.dart';

/// The image flows of one note (6.12).
class ImageFlows {
  ImageFlows({
    required this._commands,
    required this._runner,
    required this._importer,
  });

  final EditorCommands _commands;
  final ExtensionRunner _runner;
  final EditorImageImporter? Function() _importer;

  /// The ExtensionRunner id every image flow runs under (② one at a time).
  static const runId = 'editor.image';

  /// The sources the slot offers, in ImageImportSource order; empty without
  /// a slot (then every image UI is hidden — 6.12.1, E-7).
  static List<core.ImageImportSource> sourcesOf(
    EditorImageImporter? importer,
  ) => [
    if (importer != null)
      for (final s in core.ImageImportSource.values)
        if (importer.sources.contains(s)) s,
  ];

  /// Whether the slot offers the clipboard source (the context menu's
  /// '이미지 붙여넣기' and ⌘V — 6.8).
  static bool canPasteImage(EditorImageImporter? importer) =>
      importer?.sources.contains(core.ImageImportSource.clipboard) ?? false;

  /// Whether a picker is open now.
  bool get busy => _runner.isRunning(runId);

  /// Insert menu '이미지 › [source]' (6.12.2): the image on the current
  /// page, centred on its visible part, selected with origin insert.
  Future<void> insert(core.ImageImportSource source, {VoidCallback? close}) =>
      _pick(
        source,
        close,
        (image) => _commands.insertImage(image, origin: SelectionOrigin.insert),
      );

  /// '이미지 붙여넣기' — the context menu (centred on [screenPoint], the
  /// long-press point, when it is on a page) and ⌘V (no point — the
  /// visible centre): source clipboard, selected with origin paste (6.6.3).
  Future<void> paste({Offset? screenPoint, VoidCallback? close}) => _pick(
    core.ImageImportSource.clipboard,
    close,
    (image) => _commands.insertImage(
      image,
      screenPoint: screenPoint,
      origin: SelectionOrigin.paste,
    ),
  );

  /// Add-page sheet '이미지 › [source]' (6.12.3): [base] and [placement]
  /// are the sheet's values at the press.
  Future<void> insertPage(
    core.ImageImportSource source, {
    required core.Page base,
    required AddPagePlacement placement,
    VoidCallback? close,
  }) => _pick(
    source,
    close,
    (image) =>
        _commands.insertImagePage(image, base: base, placement: placement),
  );

  Future<void> _pick(
    core.ImageImportSource source,
    VoidCallback? close,
    Future<void> Function(core.ImportedImage image) then,
  ) async {
    final importer = _importer();
    if (importer == null || !importer.sources.contains(source)) return;
    final image = await _runner.run<core.ImportedImage?>(
      runId,
      (body) => importer.pick(body, source),
      close: close,
      failure: EditorStrings.imageInsertFailed,
    );
    if (image == null || _runner.bodyContext == null) return;
    await then(image);
  }
}

/// Per note (6.12, 6.19 — E2-12).
final editorImageFlowsProvider = Provider<ImageFlows>(
  (ref) => ImageFlows(
    commands: ref.watch(editorCommandsProvider),
    runner: ref.watch(editorExtensionRunnerProvider),
    importer: () => ref.read(editorImageImporterProvider),
  ),
  dependencies: [editorCommandsProvider, editorExtensionRunnerProvider],
  name: 'editorImageFlowsProvider',
);
