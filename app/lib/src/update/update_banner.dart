import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show audioRecorderServiceProvider;

import '../app/strings.dart';
import 'update_checker.dart';

/// Shows a MaterialBanner above [child] while status is UpdateAvailable.
/// Lives in MaterialApp.builder (above the Navigator): no Overlay, so the
/// banner must not use Tooltip/PopupMenu; plain TextButtons only.
///
/// The tree shape stays the same with and without the banner (the Navigator
/// below keeps its State); the top safe-area inset goes to the banner while
/// it is shown.
///
/// (2차, 01-infra 6.17 — D2-14) [새로고침] while recording
/// (`audioRecorderServiceProvider` status.isActive — UI only; with recording
/// off the default Unsupported recorder is never active) does not reload: the
/// banner adds '녹음 중에는 새로 고칠 수 없어요. 녹음을 멈춘 뒤 눌러 주세요.'
/// and the next press checks again.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  /// The build whose reload was refused while recording.
  String? _blockedSha;

  void _reload(String sha) {
    if (ref.read(audioRecorderServiceProvider).status.isActive) {
      setState(() => _blockedSha = sha);
      return;
    }
    if (_blockedSha != null) setState(() => _blockedSha = null);
    unawaited(ref.read(updateCheckerProvider.notifier).applyUpdate());
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(updateCheckerProvider);
    final remote = switch (status) {
      UpdateAvailable(:final remote) => remote,
      _ => null,
    };
    final child = widget.child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (remote != null)
          _Banner(
            message: AppStrings.updateAvailable(
              remote.buildNumber,
              remote.shortSha,
            ),
            notice: _blockedSha == remote.gitSha
                ? AppStrings.reloadBlockedByRecording
                : null,
            onLater: () => ref.read(updateCheckerProvider.notifier).dismiss(),
            onReload: () => _reload(remote.gitSha),
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
    required this.notice,
    required this.onLater,
    required this.onReload,
  });

  final String message;

  /// Second line (the reload was refused while recording).
  final String? notice;
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
          content: notice == null
              ? Text(message)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message),
                    const SizedBox(height: 4),
                    Text(notice!, style: TextStyle(color: colors.error)),
                  ],
                ),
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
