// lib/src/text_pen/text_pen_bubble.dart — (internal, text pen phase 1 —
// m5-7/05-library 6.24) the content of the editor's text pen bubble (the
// editor draws the frame; its tap converts, its long press opens the sheet):
//
//   waiting    → ⟳ '인식 중…' (+ the last text, dimmed)
//   answer     → the recognized text (≤ 3 lines) · '누르면 텍스트로 바꿔요'
//                [고치기]; nothing recognized → '글씨를 알아보지 못했어요. …'
//   failed     → '인식하지 못했어요. …' [다시]
//   no engine  → '이 기기에서는 손글씨 인식을 쓸 수 없어요.'
//   no model   → '한국어 인식 모델을 받아야 해요(약 20MB).' + the settings'
//                model row ([받기], the Wi-Fi wait, [지금 셀룰러로 받기])
import 'package:material_ui/material_ui.dart';

import '../l10n/recognition_strings.dart';
import '../ui/model_row.dart';
import '../ui/recognition_sheet.dart' show kSheetMinTapStyle;
import 'text_pen_session.dart';

/// The bubble's keys (not appendix C).
abstract final class TextPenBubbleKeys {
  static const ValueKey<String> text = ValueKey('recog.textPen.text');
  static const ValueKey<String> status = ValueKey('recog.textPen.status');
  static const ValueKey<String> retry = ValueKey('recog.textPen.retry');
  static const ValueKey<String> fix = ValueKey('recog.textPen.fix');

  /// The model row's key prefix (`'recog.textPen.model.<tag>'`).
  static const String modelPrefix = 'recog.textPen.model';
}

class TextPenBubble extends StatelessWidget {
  const TextPenBubble({
    super.key,
    required this.view,
    required this.onFix,
    required this.onRetry,
  });

  final TextPenView view;
  final VoidCallback onFix;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    Widget status(String text, {Color? color}) => Text(
      text,
      key: TextPenBubbleKeys.status,
      style: TextStyle(color: color ?? scheme.onSurfaceVariant),
    );
    Widget fix() => TextButton(
      key: TextPenBubbleKeys.fix,
      style: kSheetMinTapStyle,
      onPressed: onFix,
      child: const Text(RecognitionStrings.textPenFix),
    );

    return switch (view) {
      TextPenIdle() => const SizedBox(width: 44, height: 32),
      TextPenWaiting(:final previous) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          status(RecognitionStrings.recognizing),
          if (previous != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Opacity(
                opacity: 0.4,
                child: Text(
                  previous,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
      TextPenAnswer(:final result) when result.usable => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.text,
                  key: TextPenBubbleKeys.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyLarge,
                ),
                Text(
                  RecognitionStrings.textPenHint,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          fix(),
        ],
      ),
      TextPenAnswer() => status(RecognitionStrings.textPenNothing),
      TextPenFailed() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: status(
              RecognitionStrings.recognizeFailed,
              color: scheme.error,
            ),
          ),
          TextButton(
            key: TextPenBubbleKeys.retry,
            style: kSheetMinTapStyle,
            onPressed: onRetry,
            child: const Text(RecognitionStrings.retry),
          ),
        ],
      ),
      TextPenNoEngine() => status(RecognitionStrings.unsupported),
      TextPenNeedsModel(:final languageTag) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          status(
            RecognitionStrings.modelNeeded(
              RecognitionStrings.languageName(languageTag),
            ),
          ),
          RecognitionModelRow(
            key: ValueKey('${TextPenBubbleKeys.modelPrefix}.card'),
            languageTag: languageTag,
            keyPrefix: TextPenBubbleKeys.modelPrefix,
          ),
        ],
      ),
    };
  }
}
