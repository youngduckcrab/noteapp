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

/// Opens [builder] as a recognition sheet keyed [sheetKey]. Call it before the
/// run's first await (it reads the Navigator of [context] synchronously).
///
/// The keyed content is at most 50% of the screen height and sits on the
/// keyboard: the sheet's surface grows by viewInsets.bottom underneath it, so
/// what the user sees of the sheet stays ≤ 50% with the keyboard up too.
Future<T?> showRecognitionSheet<T>(
  BuildContext context, {
  required Key sheetKey,
  required WidgetBuilder builder,
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
        maxHeight:
            MediaQuery.sizeOf(sheetContext).height * kSheetMaxHeightFactor,
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
            style: _minTap,
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
              style: _minTap,
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
final ButtonStyle _minTap = ButtonStyle(
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
                style: _minTap,
                onPressed: onAction,
                child: Text(action),
              ),
          ],
        ),
      ),
    );
  }
}
