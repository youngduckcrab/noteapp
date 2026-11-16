// lib/src/ui/sidebar/sync_badge_indicator.dart — 05-library 6.16.1
// (LIBRARY-M1). The sync status at the bottom of the sidebar. The state is
// CORE's SyncBadge (contract 7.2.13); the words are LIBRARY's.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show SyncBadge, SyncDisplayState, clockProvider, syncBadgeProvider;

import '../../common/report_error.dart';
import '../../l10n/library_date_format.dart';
import '../../l10n/library_strings.dart';
import '../layout/library_metrics.dart';

/// Watches core.syncBadgeProvider (contract 7.2.13). Tap → onTap (LibraryScreen.onOpenSettings).
/// Loading or provider error → treated as SyncBadge.off (an error is reported once).
/// (v2.14-ui, UI stage 1) Nothing is drawn while sync is off (the floppy
/// '이 기기에 저장' was noise): it shows only while sync is on (done /
/// in progress) or has a problem (offline / error).
class SyncBadgeIndicator extends ConsumerWidget {
  const SyncBadgeIndicator({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(syncBadgeProvider);
    final SyncBadge badge;
    if (async.hasError) {
      reportLibraryErrorOnce(
        ProviderScope.containerOf(context, listen: false),
        async.error!,
        async.stackTrace,
        'syncBadgeProvider',
      );
      badge = SyncBadge.off;
    } else {
      badge = async.value ?? SyncBadge.off;
    }
    if (badge.display == SyncDisplayState.off) return const SizedBox.shrink();
    final look = SyncBadgeLook.of(badge, now: ref.watch(clockProvider).now());
    final theme = Theme.of(context);
    final color = switch (look.role) {
      SyncBadgeColorRole.onSurfaceVariant => theme.colorScheme.onSurfaceVariant,
      SyncBadgeColorRole.primary => theme.colorScheme.primary,
      SyncBadgeColorRole.error => theme.colorScheme.error,
    };
    return Tooltip(
      message: look.tooltip,
      // The sync state, not a name: also on a long press (HoverNames makes
      // plain tooltips hover-only).
      triggerMode: TooltipTriggerMode.longPress,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: LibraryMetrics.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(look.icon, size: 20, color: color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        look.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure mapping (unit-tested): label / tooltip / icon / color role for one badge.
@immutable
final class SyncBadgeLook {
  const SyncBadgeLook({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.role,
  });

  /// The 6.16.1 table. [now] formats lastSyncedAt ('마지막 동기화 오늘 오후
  /// 2:05'). A negative pendingChanges counts as 0. issueCode is not used yet
  /// (per-issue wording is M4, 5.5 Y-3).
  factory SyncBadgeLook.of(SyncBadge badge, {required DateTime now}) {
    switch (badge.display) {
      case SyncDisplayState.off:
        return const SyncBadgeLook(
          icon: Icons.save_outlined,
          label: LibraryStrings.syncOff,
          tooltip: LibraryStrings.syncOffTooltip,
          role: SyncBadgeColorRole.onSurfaceVariant,
        );
      case SyncDisplayState.done:
        final at = badge.lastSyncedAt;
        return SyncBadgeLook(
          icon: Icons.cloud_done_outlined,
          label: LibraryStrings.syncDone,
          tooltip: at == null
              ? LibraryStrings.syncDone
              : LibraryStrings.syncDoneTooltip(formatLibraryDate(at, now: now)),
          role: SyncBadgeColorRole.onSurfaceVariant,
        );
      case SyncDisplayState.inProgress:
        final n = badge.pendingChanges;
        return SyncBadgeLook(
          icon: Icons.sync,
          label: LibraryStrings.syncInProgressCount(n),
          tooltip: n > 0
              ? LibraryStrings.syncPendingTooltip(n)
              : LibraryStrings.syncInProgress,
          role: SyncBadgeColorRole.primary,
        );
      case SyncDisplayState.offline:
        return const SyncBadgeLook(
          icon: Icons.cloud_off_outlined,
          label: LibraryStrings.syncOffline,
          tooltip: LibraryStrings.syncOfflineTooltip,
          role: SyncBadgeColorRole.onSurfaceVariant,
        );
      case SyncDisplayState.error:
        return const SyncBadgeLook(
          icon: Icons.sync_problem,
          label: LibraryStrings.syncError,
          tooltip: LibraryStrings.syncErrorTooltip,
          role: SyncBadgeColorRole.error,
        );
    }
  }

  final IconData icon;
  final String label;
  final String tooltip;
  final SyncBadgeColorRole role;

  @override
  bool operator ==(Object other) =>
      other is SyncBadgeLook &&
      other.icon == icon &&
      other.label == label &&
      other.tooltip == tooltip &&
      other.role == role;

  @override
  int get hashCode => Object.hash(icon, label, tooltip, role);

  @override
  String toString() => 'SyncBadgeLook($label, "$tooltip", ${role.name})';
}

enum SyncBadgeColorRole { onSurfaceVariant, primary, error }
