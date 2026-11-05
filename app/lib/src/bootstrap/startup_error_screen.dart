import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/strings.dart';
import 'app_bootstrapper.dart';

/// Shown when a critical module failed (6.7): title, [BootstrapFailure.
/// userMessage], folded details (exception and module id) and the buttons
/// [다시 시도] [진단 정보 복사] [(offersReload) 새로고침]
/// [(onResetLocalData) 이 기기 데이터 지우고 다시 시작 — two-step confirm].
///
/// Needs a MaterialApp above it (BootstrapApp provides one).
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    super.key,
    required this.failure,
    required this.diagnostics,
    required this.onRetry,
    this.onResetLocalData,
    this.onReload,
  });
  final BootstrapFailure failure;

  /// DiagnosticReport text, copied by the "진단 정보 복사" button.
  final String diagnostics;
  final VoidCallback onRetry;

  /// failure.resetLocalData wrapped by BootstrapApp (then retry). Two-step
  /// confirm. Hidden when null (storageUnavailable, newerSchema, timeouts …).
  final Future<void> Function()? onResetLocalData;

  /// WebPlatform.reload, shown when failure.offersReload.
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reload = failure.offersReload ? onReload : null;
    final reset = onResetLocalData;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.startupFailedTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    failure.userMessage,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text(AppStrings.startupDetails),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        AppStrings.startupDetailModule(failure.moduleId),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        '${failure.error}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text(AppStrings.retry),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _copyDiagnostics(context),
                    child: const Text(AppStrings.copyDiagnostics),
                  ),
                  if (reload != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: reload,
                      child: const Text(AppStrings.reload),
                    ),
                  ],
                  if (reset != null) ...[
                    const SizedBox(height: 24),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: () => _confirmReset(context, reset),
                      child: const Text(AppStrings.resetLocalData),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyDiagnostics(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: diagnostics));
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.diagnosticsCopied)),
    );
  }

  /// ① warning [취소] [계속] → ② "정말 지울까요?" [취소] [지우기] → reset.
  /// A failed reset shows "데이터를 지우지 못했어요." (BootstrapApp logs it).
  Future<void> _confirmReset(
    BuildContext context,
    Future<void> Function() reset,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final first = await _confirm(
      context,
      AppStrings.resetConfirmFirst,
      AppStrings.proceed,
    );
    if (!first || !context.mounted) return;
    final second = await _confirm(
      context,
      AppStrings.resetConfirmSecond,
      AppStrings.erase,
    );
    if (!second) return;
    try {
      await reset();
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.resetFailed)),
      );
    }
  }

  Future<bool> _confirm(BuildContext context, String message, String action) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ).then((value) => value ?? false);
}
