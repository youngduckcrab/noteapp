// lib/src/ui/sheets.dart — bottom sheets of the panel (m5-7/06-pdf 6.13.3, 7.4.10 '높이 ≤
// 50%'). Internal. T36a: the consent sheet (first recording on this device — 6.13.3 ①). T36b:
// the recording menu (rename / delete), the name sheet, the confirm sheets and the menu of a
// draft that could not be recovered (web download · 지우기).
import 'package:material_ui/material_ui.dart';

import 'strings_ko.dart';

/// The fixed consent notice with [취소][녹음 시작]; true = start.
Future<bool> showConsentSheet(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              MediaStringsKo.consent,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(MediaStringsKo.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(MediaStringsKo.startRecording),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

BoxConstraints _halfHeight(BuildContext context) =>
    BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5);

enum RecordingAction { rename, delete }

/// [⋯] of a recording: '이름 바꾸기' / '삭제'.
Future<RecordingAction?> showRecordingActionsSheet(BuildContext context) =>
    showModalBottomSheet<RecordingAction>(
      context: context,
      constraints: _halfHeight(context),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text(MediaStringsKo.rename),
              onTap: () => Navigator.of(context).pop(RecordingAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text(MediaStringsKo.delete),
              onTap: () => Navigator.of(context).pop(RecordingAction.delete),
            ),
          ],
        ),
      ),
    );

/// The title as saved: trimmed, at most 100 runes (CORE 7.2.4); empty → null (the default name).
String? normalizeRecordingTitle(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  final runes = t.runes.toList();
  if (runes.length <= 100) return t;
  return String.fromCharCodes(runes.take(100)).trim();
}

/// The name sheet: the field starts with [current] (null = empty — the default name). Returns
/// `(title: …)` on [저장] (title null = back to the default), null when cancelled.
Future<({String? title})?> showRenameSheet(
  BuildContext context, {
  required String? current,
}) => showModalBottomSheet<({String? title})>(
  context: context,
  isScrollControlled: true,
  constraints: _halfHeight(context),
  builder: (context) => _RenameSheet(current: current),
);

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.current});
  final String? current;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() =>
      Navigator.of(context).pop((title: normalizeRecordingTitle(_text.text)));

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            MediaStringsKo.rename,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(
              hintText: MediaStringsKo.nameHint,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(MediaStringsKo.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: const Text(MediaStringsKo.save),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// [message] with [취소][confirm]; true = confirmed.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String message,
  required String confirm,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    constraints: _halfHeight(context),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(MediaStringsKo.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(confirm),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// [⋯] of the stuck-draft row: (web) the download button inside the sheet — both steps happen
/// there — and '지우기'. true = '지우기' chosen.
Future<bool> showStuckDraftSheet(
  BuildContext context, {
  Widget? download,
}) async {
  final discard = await showModalBottomSheet<bool>(
    context: context,
    constraints: _halfHeight(context),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (download != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: download,
                ),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text(MediaStringsKo.discardDraft),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    ),
  );
  return discard ?? false;
}
