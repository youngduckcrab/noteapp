// lib/src/ui/sheets.dart — bottom sheets of the panel (m5-7/06-pdf 6.13.3, 7.4.10 '높이 ≤
// 50%'). Internal. T36a: the consent sheet (first recording on this device — 6.13.3 ①). T36b
// adds the name / delete / download sheets.
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
