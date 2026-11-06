// lib/src/di/editor_image_importer.dart — 2nd-round contract m5-7/00-overview
// 7.2.10, m5-7/04-editor 4.2, 4.3.1, 6.12.
//
// The image slot: INFRA's FeatureWiringModule overrides
// editorImageImporterProvider with media_io's picker (contract 7.3.3). With
// the default null the editor hides image insert, image paste and the image
// page row. R2-B5 (foundation): the type and the provider only; the flows
// that call it come in E2-12.
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

/// Image picking + normalization lives in media_io; EDITOR only calls this slot.
///
/// The editor calls [pick] synchronously inside the button's onPressed, with
/// the editor body's context, and closes its menu or sheet after that call
/// (contract 7.2.10 (v2.1)).
@immutable
class EditorImageImporter {
  const EditorImageImporter({required this.sources, required this.pick});
  final Set<core.ImageImportSource> sources;
  final Future<core.ImportedImage?> Function(
    BuildContext context,
    core.ImageImportSource source,
  )
  pick;

  static const _sources = SetEquality<core.ImageImportSource>();

  /// Every field, [pick] as a function (04-editor 4.3.1).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorImageImporter &&
          _sources.equals(other.sources, sources) &&
          other.pick == pick;

  @override
  int get hashCode => Object.hash(_sources.hash(sources), pick);

  @override
  String toString() =>
      'EditorImageImporter(${[for (final s in sources) s.name].join(', ')})';
}

final editorImageImporterProvider = Provider<EditorImageImporter?>(
  (ref) => null,
  name: 'editorImageImporterProvider',
); // null → image insert / image page hidden
