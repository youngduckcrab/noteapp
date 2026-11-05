// lib/src/model/entity_json.dart — contract 00-overview 7.2.6 / CORE 4.2, 6.3.
// (v2.0) pageObject / handwriting — 2nd-round 02-core 6.3.
import 'asset.dart';
import 'folder.dart';
import 'handwriting.dart';
import 'note.dart';
import 'page.dart';
import 'pen_preset.dart';
import 'stroke.dart';
import 'sync_entity.dart';

abstract final class EntityJson {
  /// Throws FormatException.
  static SyncEntity decode(EntityKind kind, Map<String, Object?> json) =>
      switch (kind) {
        EntityKind.folder => Folder.fromJson(json),
        EntityKind.note => Note.fromJson(json),
        EntityKind.page => Page.fromJson(json),
        EntityKind.stroke => Stroke.fromJson(json),
        EntityKind.penPreset => PenPreset.fromJson(json),
        EntityKind.asset => Asset.fromJson(json),
        EntityKind.recording => Recording.fromJson(json),
        EntityKind.setting => SettingValue.fromJson(json),
        // (v2.0, 02-core 6.3) the decoders are CORE T20a (UnimplementedError until then).
        EntityKind.pageObject => PageObject.fromJson(json),
        EntityKind.handwriting => HandwritingText.fromJson(json),
      };
}
