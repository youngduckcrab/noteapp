// Links (08-markdown 8.6, B-6): nothing opens by itself. A tap shows a sheet with the
// whole address, [복사], [외부 앱에서 열기] (only when the app gave the open-link slot
// and the scheme is http, https, mailto or tel) and [취소]. '#heading' links are handled
// by the screen (scroll inside the document) before this sheet.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../markdown_keys.dart';
import '../slots_impl.dart';
import '../strings_ko.dart';

const Set<String> kOpenableSchemes = {'http', 'https', 'mailto', 'tel'};

/// Whether [href] may be offered to the open-link slot.
Uri? openableUri(String href) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return null;
  return kOpenableSchemes.contains(uri.scheme.toLowerCase()) ? uri : null;
}

/// Shows the link sheet for [href].
Future<void> showLinkSheet(
  BuildContext context, {
  required String href,
  required MarkdownOpenLinkAction? openLink,
  VoidCallback? onEdit,
}) {
  final uri = openLink == null ? null : openableUri(href);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final t = StyleTokens.of(sheetContext);
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          key: MarkdownKeys.linkSheet,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                MdStrings.linkTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                href,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: t.textPrimary,
                ),
              ),
              if (uri == null && openableUri(href) == null) ...[
                const SizedBox(height: 6),
                Text(
                  MdStrings.linkCopyOnly,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onEdit != null)
                    TextButton.icon(
                      key: MarkdownKeys.linkSheetEdit,
                      icon: const AppIcon(AppIconKind.editSource, size: 18),
                      label: const Text(MdStrings.linkEditBlock),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onEdit();
                      },
                    ),
                  TextButton(
                    key: MarkdownKeys.linkSheetCancel,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text(MdStrings.cancel),
                  ),
                  OutlinedButton.icon(
                    key: MarkdownKeys.linkSheetCopy,
                    icon: const AppIcon(AppIconKind.copyText, size: 18),
                    label: const Text(MdStrings.linkCopy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: href));
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                      say(MdStrings.copied);
                    },
                  ),
                  if (uri != null)
                    FilledButton.icon(
                      key: MarkdownKeys.linkSheetOpen,
                      icon: const AppIcon(AppIconKind.openExternal, size: 18),
                      label: const Text(MdStrings.linkOpen),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        var ok = false;
                        try {
                          ok = await openLink!(uri);
                        } on Object {
                          ok = false;
                        }
                        if (!ok) say(MdStrings.linkOpenFailed);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
