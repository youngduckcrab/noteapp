// lib/src/repo/pen_preset_repository.dart — contract 00-overview 7.2.9 / CORE 4.5.
// Contract comments are kept verbatim (they contain <placeholders>).
// ignore_for_file: unintended_html_in_doc_comment
import '../common/ids.dart';
import '../model/pen_preset.dart';
import '../model/pen_style.dart';

abstract interface class PenPresetRepository {
  Stream<List<PenPreset>> watchPresets(); // active, ordered by (sortKey, id)
  Future<List<PenPreset>> getPresets();

  /// name: trimmed 1..60 chars (EDITOR's input UI allows 1..20).
  Future<PenPreset> createPreset({
    required String name,
    required StrokeStyle style,
    String? group,
    bool pinned = true,
    PresetId? after,
  });
  Future<void> updatePreset(PenPreset preset); // name, style, group, pinned
  Future<void> reorderPreset(PresetId id, {PresetId? after, PresetId? before});

  /// Rewrites sortKeys so active presets follow [orderedIds]; unknown ids ignored,
  /// active presets not listed keep their relative order after the listed ones. ONE commit.
  Future<void> reorderPresets(List<PresetId> orderedIds);
  Future<void> deletePreset(PresetId id);

  /// Creates the 5 default presets once per database (6.2.2: ids 'preset-default-<wireName>',
  /// Korean names, sortKeys a0..a4, pinned, seed HLC). Deleted defaults are never re-created.
  Future<void> ensureDefaults();
}
