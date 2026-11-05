import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/strings.dart';
import 'update_checker.dart';

/// Shows a MaterialBanner above [child] while status is UpdateAvailable.
/// Lives in MaterialApp.builder (above the Navigator): no Overlay, so the
/// banner must not use Tooltip/PopupMenu; plain TextButtons only.
///
/// The tree shape stays the same with and without the banner (the Navigator
/// below keeps its State); the top safe-area inset goes to the banner while
/// it is shown.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateCheckerProvider);
    final remote = switch (status) {
      UpdateAvailable(:final remote) => remote,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (remote != null)
          _Banner(
            message: AppStrings.updateAvailable(
              remote.buildNumber,
              remote.shortSha,
            ),
            onLater: () => ref.read(updateCheckerProvider.notifier).dismiss(),
            onReload: () => unawaited(
              ref.read(updateCheckerProvider.notifier).applyUpdate(),
            ),
          ),
        Expanded(
          key: const ValueKey<String>('update-banner-child'),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: remote != null,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.onLater,
    required this.onReload,
  });

  final String message;
  final VoidCallback onLater;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        bottom: false,
        child: MaterialBanner(
          elevation: 0,
          backgroundColor: colors.surfaceContainerLow,
          leading: Icon(Icons.system_update_alt, color: colors.primary),
          content: Text(message),
          actions: [
            TextButton(onPressed: onLater, child: const Text(AppStrings.later)),
            TextButton(
              onPressed: onReload,
              child: const Text(AppStrings.reload),
            ),
          ],
        ),
      ),
    );
  }
}
