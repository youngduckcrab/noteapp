import 'package:material_ui/material_ui.dart';

import '../app/strings.dart';

/// Placeholder of the `/settings` screen (foundation step B8).
///
/// I9 replaces it with SettingsScreen: the frame plus the EDITOR, LIBRARY and
/// shell sections (docs/plans/01-infra.md 4.5.8).
class SettingsPlaceholderScreen extends StatelessWidget {
  const SettingsPlaceholderScreen({super.key, required this.onClose});

  /// Back button of the app bar.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: AppStrings.back,
          onPressed: onClose,
        ),
        title: const Text(AppStrings.settings),
      ),
      body: const Center(child: Text(AppStrings.settingsPlaceholder)),
    );
  }
}
