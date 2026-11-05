// lib/src/ui/dialogs/dialog_frame.dart — the frame of the library's form
// dialogs (6.12; L13 reuses it): title, a scrolling body and the action row,
// at most LibraryMetrics.dialogMaxWidth wide. Dialog itself keeps the frame
// above the on-screen keyboard (viewInsets), the body scrolls.
import 'package:material_ui/material_ui.dart';

import '../layout/library_metrics.dart';

class LibraryDialogFrame extends StatelessWidget {
  const LibraryDialogFrame({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.maxWidth = LibraryMetrics.dialogMaxWidth,
  });

  final String title;
  final List<Widget> body;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.headlineSmall),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: body,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled block of a form dialog: label (labelLarge), 8, the control,
/// then 20 below.
class DialogSection extends StatelessWidget {
  const DialogSection({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// '위치' + the read-only location ('홈 › 수학').
class DialogLocationRow extends StatelessWidget {
  const DialogLocationRow({
    super.key,
    required this.label,
    required this.location,
  });

  final String label;
  final String location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The name / title field of a form dialog: starts with [controller]'s text
/// fully selected, at most kMaxItemNameLength characters (no counter).
class DialogNameField extends StatelessWidget {
  const DialogNameField({
    super.key,
    required this.controller,
    required this.label,
    required this.maxLength,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final int maxLength;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(labelText: label, counterText: ''),
        textInputAction: TextInputAction.done,
        onSubmitted: onSubmitted,
      ),
    );
  }
}
