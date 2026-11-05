// lib/src/ui/toolbar/sync_badge_icon.dart — 04-editor 6.9.1 ([☁]).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../editor_strings.dart';

/// `core.syncBadgeProvider` (contract 7.2.13): hidden — no space either —
/// while off, loading or failed. 20 px icon in a 48 px touch area, no tap
/// action (account and sync settings live on INFRA's settings screen).
class EditorSyncBadgeIcon extends ConsumerWidget {
  const EditorSyncBadgeIcon({super.key});

  static const iconKey = ValueKey('editor.toolbar.sync');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = ref.watch(core.syncBadgeProvider).value;
    if (badge == null || badge.display == core.SyncDisplayState.off) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label, Color color) = switch (badge.display) {
      core.SyncDisplayState.off || core.SyncDisplayState.done => (
        Icons.cloud_done,
        EditorStrings.syncDone,
        scheme.onSurfaceVariant,
      ),
      core.SyncDisplayState.inProgress => (
        Icons.cloud_sync,
        EditorStrings.syncInProgress,
        scheme.onSurfaceVariant,
      ),
      core.SyncDisplayState.offline => (
        Icons.cloud_off,
        EditorStrings.syncOffline,
        scheme.onSurfaceVariant,
      ),
      core.SyncDisplayState.error => (
        Icons.sync_problem,
        EditorStrings.syncError,
        scheme.error,
      ),
    };
    final pending =
        badge.display == core.SyncDisplayState.inProgress &&
        badge.pendingChanges > 0;
    final glyph = Icon(icon, size: 20, color: color);
    return Semantics(
      key: iconKey,
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: pending
                ? Badge(label: Text('${badge.pendingChanges}'), child: glyph)
                : glyph,
          ),
        ),
      ),
    );
  }
}
