import 'package:material_ui/material_ui.dart';

import '../app/strings.dart';

/// Shown for any location no route matches (docs/plans/01-infra.md 6.6):
/// a short message, the location and a button back to the library.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({
    super.key,
    required this.location,
    required this.onGoHome,
  });

  /// The location that did not match, as the router saw it.
  final String location;

  /// Goes to `/`.
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.notFoundTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.notFoundDetail,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  location,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onGoHome,
                  child: const Text(AppStrings.goHome),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
