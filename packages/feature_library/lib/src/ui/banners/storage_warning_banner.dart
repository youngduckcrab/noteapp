// lib/src/ui/banners/storage_warning_banner.dart — 05-library 6.16.2
// (LIBRARY-S3, contract 7.2.12 / 7.4.5). The ONE condition is CORE's
// storageWarningOf; LIBRARY never compares consecutiveFailures / isDurable.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show
        StorageWarning,
        noteStoreProvider,
        persistenceStatusProvider,
        storageInfoProvider,
        storageWarningOf;

import '../../l10n/library_strings.dart';

/// w = storageWarningOf(ref.watch(storageInfoProvider), status) where status =
///   ref.watch(persistenceStatusProvider).value ?? ref.watch(noteStoreProvider).persistenceStatus
/// The fallback is for the FIRST FRAME only: persistenceStatusStream emits the current value
/// right after listen (7.2.12 v1.1) but asynchronously, so the provider is AsyncLoading for
/// one frame; after that the stream value is always used.
/// null → 0 height. writeFailing → error banner, not dismissible.
/// notDurable → warning banner, dismissible for this app session (State only, not persisted;
/// shown again if the warning changes to writeFailing).
class StorageWarningBanner extends ConsumerStatefulWidget {
  const StorageWarningBanner({super.key});

  @override
  ConsumerState<StorageWarningBanner> createState() =>
      _StorageWarningBannerState();
}

class _StorageWarningBannerState extends ConsumerState<StorageWarningBanner> {
  /// [닫기] on the notDurable banner (this app session only).
  bool _notDurableDismissed = false;

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(storageInfoProvider);
    final status =
        ref.watch(persistenceStatusProvider).value ??
        ref.watch(noteStoreProvider).persistenceStatus;
    final warning = storageWarningOf(info, status);
    final scheme = Theme.of(context).colorScheme;
    switch (warning) {
      case null:
        return const SizedBox.shrink();
      case StorageWarning.writeFailing:
        return _BannerBody(
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
          icon: Icons.error_outline,
          message: LibraryStrings.storageWriteFailing,
        );
      case StorageWarning.notDurable:
        if (_notDurableDismissed) return const SizedBox.shrink();
        return _BannerBody(
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
          icon: Icons.warning_amber_outlined,
          message: LibraryStrings.storageNotDurable,
          onClose: () => setState(() => _notDurableDismissed = true),
        );
    }
  }
}

/// `[icon][message (wraps)][닫기]`, at least 48 high (6.16.2).
class _BannerBody extends StatelessWidget {
  const _BannerBody({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.message,
    this.onClose,
  });

  final Color background, foreground;
  final IconData icon;
  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: background,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
            child: Row(
              children: [
                Icon(icon, color: foreground, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      message,
                      style: textTheme.bodyMedium?.copyWith(color: foreground),
                    ),
                  ),
                ),
                if (onClose != null)
                  TextButton(
                    onPressed: onClose,
                    style: TextButton.styleFrom(foregroundColor: foreground),
                    child: const Text(LibraryStrings.close),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
