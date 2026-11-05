import 'package:material_ui/material_ui.dart';

/// Foundation step B1 entry point: a placeholder screen only.
///
/// B8 connects the minimal router and the placeholder screens; I5 replaces
/// this file with `runNoteApp()` (docs/plans/01-infra.md 8.1 / 8.2).
void main() {
  runApp(const NoteAppPlaceholder());
}

/// Placeholder root widget of the foundation step (material_ui only, R7).
class NoteAppPlaceholder extends StatelessWidget {
  const NoteAppPlaceholder({super.key});

  /// Placeholder text shown until the app shell is connected (B8).
  static const String message = '필기노트를 준비하고 있어요.';

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: '필기노트',
      locale: Locale('ko'),
      home: Scaffold(body: Center(child: Text(message))),
    );
  }
}
