// lib/src/ui/recognition_sheet.dart — (internal) m5-7/05-library 6.12,
// contract 7.4.10: the one way a recognition sheet opens and the parts every
// sheet shares.
//
// - showRecognitionSheet: material_ui showModalBottomSheet (isScrollControlled,
//   useSafeArea); the content at most 50% of the screen height, lifted above
//   the keyboard by viewInsets.bottom; it scrolls inside the sheet. No own
//   Navigator.push, global Overlay or dialog.
// - RecognitionSheetHeader: [취소] title [primary] (keys recog.sheet.cancel /
//   recog.sheet.primary — appendix C), tap targets ≥ 44×44.
// - SheetNotice: the in-sheet notice line (icon + text + optional action) —
//   failures are shown here, never as an exception out of run (G-1).
// Colours come from Theme.of(context).colorScheme only.
import 'package:material_ui/material_ui.dart';

/// Appendix C keys.
const ValueKey<String> kSheetPrimaryKey = ValueKey('recog.sheet.primary');
const ValueKey<String> kSheetSecondaryKey = ValueKey('recog.sheet.secondary');
const ValueKey<String> kSheetCancelKey = ValueKey('recog.sheet.cancel');

/// The largest share of the screen height a sheet may take (7.4.10).
const double kSheetMaxHeightFactor = 0.5;

/// Sheets outside the editor (the A-4 lab, the math fixture pad — 6.20,
/// 6.14.7) may take up to 90%: the 50% rule is for UI over the page.
const double kOutsideEditorSheetMaxHeightFactor = 0.9;

/// Opens [builder] as a recognition sheet keyed [sheetKey]. Call it before the
/// run's first await (it reads the Navigator of [context] synchronously).
///
/// The keyed content is at most 50% of the screen height and sits on the
/// keyboard: the sheet's surface grows by viewInsets.bottom underneath it, so
/// what the user sees of the sheet stays ≤ 50% with the keyboard up too.
/// [maxHeightFactor] is [kOutsideEditorSheetMaxHeightFactor] for the sheets
/// opened outside the editor.
Future<T?> showRecognitionSheet<T>(
  BuildContext context, {
  required Key sheetKey,
  required WidgetBuilder builder,
  double maxHeightFactor = kSheetMaxHeightFactor,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * maxHeightFactor,
      ),
      child: KeyedSubtree(key: sheetKey, child: builder(sheetContext)),
    ),
  ),
);

/// [취소] title [primary] — the primary is disabled when [onPrimary] is null.
class RecognitionSheetHeader extends StatelessWidget {
  const RecognitionSheetHeader({
    super.key,
    required this.title,
    required this.cancelLabel,
    required this.onCancel,
    this.primaryLabel,
    this.onPrimary,
  });

  final String title;
  final String cancelLabel;
  final VoidCallback onCancel;

  /// null → no primary button (a sheet that only informs).
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = primaryLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          TextButton(
            key: kSheetCancelKey,
            style: kSheetMinTapStyle,
            onPressed: onCancel,
            child: Text(cancelLabel),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (primary != null)
            FilledButton(
              key: kSheetPrimaryKey,
              style: kSheetMinTapStyle,
              onPressed: onPrimary,
              child: Text(primary),
            )
          else
            const SizedBox(width: 64),
        ],
      ),
    );
  }
}

/// ≥ 44×44 tap targets on every platform (7.4.10).
final ButtonStyle kSheetMinTapStyle = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
  tapTargetSize: MaterialTapTargetSize.padded,
);

/// The kind of a [SheetNotice].
enum SheetNoticeKind { info, error }

/// One notice line inside a sheet: icon + text (+ an action button).
class SheetNotice extends StatelessWidget {
  const SheetNotice({
    super.key,
    required this.text,
    this.kind = SheetNoticeKind.info,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final SheetNoticeKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = kind == SheetNoticeKind.error
        ? scheme.error
        : scheme.onSurfaceVariant;
    final action = actionLabel;
    return Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Icon(
              kind == SheetNoticeKind.error
                  ? Icons.error_outline
                  : Icons.info_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: color)),
            ),
            if (action != null)
              TextButton(
                style: kSheetMinTapStyle,
                onPressed: onAction,
                child: Text(action),
              ),
          ],
        ),
      ),
    );
  }
}

/// Appendix C keys of the consent card.
const ValueKey<String> kConsentAgreeKey = ValueKey('recog.consent.agree');
const ValueKey<String> kConsentManualKey = ValueKey('recog.consent.manual');

/// The G-3 consent card (6.11.5, 6.14.5): what is sent, to whom, how to turn
/// it off — [동의하고 쓰기] [직접 입력]. Scrolls inside its box when the box is
/// small (the math pad lays it over its handwriting area).
class ConsentCard extends StatelessWidget {
  const ConsentCard({
    super.key,
    required this.title,
    required this.body,
    required this.agreeLabel,
    required this.manualLabel,
    required this.onAgree,
    required this.onManual,
  });

  final String title;
  final String body;
  final String agreeLabel;
  final String manualLabel;

  /// null while the agreement is being saved (the button is disabled).
  final VoidCallback? onAgree;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  key: kConsentManualKey,
                  style: kSheetMinTapStyle,
                  onPressed: onManual,
                  child: Text(manualLabel),
                ),
                FilledButton(
                  key: kConsentAgreeKey,
                  style: kSheetMinTapStyle,
                  onPressed: onAgree,
                  child: Text(agreeLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
