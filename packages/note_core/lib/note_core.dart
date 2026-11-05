/// Document model, local storage, undo and sync outbox (pure Dart, web
/// safe).
///
/// Owned by CORE (docs/plans/02-core.md). Public API = contract
/// 00-overview 7.2.2 ~ 7.2.14 (CORE 4.1 ~ 4.9). Everything under `src/` is
/// private; other areas import only this file (and `dev_tools.dart` for the
/// developer menu, `testing.dart` / `testing_vm.dart` from `test/`).
library;

export 'src/assets/asset_store.dart';
export 'src/common/errors.dart';
export 'src/common/geometry.dart';
export 'src/common/hlc.dart';
export 'src/common/ids.dart';
export 'src/common/sort_keys.dart';
export 'src/edit/applied_edit.dart';
export 'src/edit/commands.dart';
export 'src/edit/page_draft.dart';
export 'src/model/asset.dart';
export 'src/model/entity_json.dart';
export 'src/model/folder.dart';
export 'src/model/note.dart';
export 'src/model/page.dart';
export 'src/model/page_background.dart';
export 'src/model/page_size.dart';
export 'src/model/page_template.dart';
export 'src/model/pen_preset.dart';
export 'src/model/pen_style.dart';
export 'src/model/pressure_curve.dart';
export 'src/model/stroke.dart';
export 'src/model/stroke_points.dart';
export 'src/model/sync_entity.dart' hide readVersion;
export 'src/providers.dart';
export 'src/repo/content_reader.dart';
export 'src/repo/events.dart';
export 'src/repo/folder_tree.dart';
export 'src/repo/library_repository.dart';
export 'src/repo/library_types.dart';
export 'src/repo/note_store.dart';
export 'src/repo/pen_preset_repository.dart';
export 'src/repo/settings_repository.dart';
export 'src/repo/status.dart';
export 'src/repo/trash_repository.dart';
export 'src/session/note_session.dart';
export 'src/session/page_content.dart';
export 'src/sync/field_versions.dart';
export 'src/sync/merge.dart';
export 'src/sync/outbox_types.dart';
export 'src/sync/sync_display.dart';
export 'src/sync/sync_store.dart';
