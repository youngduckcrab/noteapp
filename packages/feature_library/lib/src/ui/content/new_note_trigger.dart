// lib/src/ui/content/new_note_trigger.dart — what every in-content '새 노트'
// control does (the grid's '새 노트' tile, the empty state button): the new
// note flow (6.12 — dialog, create, open) into [folderId]. The control is
// disabled while the flow runs.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../dialogs/create_flows.dart';

class NewNoteTrigger extends StatefulWidget {
  const NewNoteTrigger({
    super.key,
    required this.folderId,
    required this.builder,
  });

  /// Where the note goes (null = 홈).
  final FolderId? folderId;

  /// [onPressed] is null while a creation is in flight (no double taps).
  final Widget Function(BuildContext context, VoidCallback? onPressed) builder;

  @override
  State<NewNoteTrigger> createState() => _NewNoteTriggerState();
}

class _NewNoteTriggerState extends State<NewNoteTrigger> {
  /// CORE write Futures stay pending while a failed commit is retried
  /// (contract 7.2.9 v1.2), so the control stays disabled meanwhile.
  bool _creating = false;

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      await runNewNoteFlow(context, folderId: widget.folderId);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _creating ? null : _create);
}
