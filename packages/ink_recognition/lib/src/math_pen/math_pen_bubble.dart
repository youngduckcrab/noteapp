// lib/src/math_pen/math_pen_bubble.dart — (internal, math pen phase 1 —
// docs/plans/m5-7/research/math-pen-phase1.md 6.2, 10) the content of the
// editor's math pen bubble (the editor draws the frame and takes the tap):
//
//   waiting  → ⟳ '인식 중…' (+ the last formula, dimmed)
//   answer   → INK MathPreview of the formula | an unusable one: its LaTeX +
//              '그릴 수 없는 결과예요. 눌러서 고쳐요.'
//   failed   → the 6.11.4 text + [다시]
//   consent  → '외부 수식 인식 동의가 필요해요. …' (the tap opens the card)
//   no engine→ '수식 인식이 꺼져 있어요.' + [기기에서 수식 인식 켜기] (where
//              the platform has a model manager — settings' tile in a sheet)
//              + [LaTeX로 입력]; when that sheet closes the group is
//              recognized again (the engine may be on now)
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';

import '../l10n/recognition_strings.dart';
import '../ondevice/on_device_providers.dart';
import '../settings/on_device_math_tile.dart';
import '../ui/recognition_sheet.dart';
import 'math_pen_session.dart';

/// The bubble's keys (not appendix C).
abstract final class MathPenBubbleKeys {
  static const ValueKey<String> preview = ValueKey('recog.mathPen.preview');
  static const ValueKey<String> status = ValueKey('recog.mathPen.status');
  static const ValueKey<String> retry = ValueKey('recog.mathPen.retry');
  static const ValueKey<String> enableOnDevice = ValueKey(
    'recog.mathPen.enableOnDevice',
  );
  static const ValueKey<String> typeLatex = ValueKey('recog.mathPen.typeLatex');
  static const ValueKey<String> onDeviceSheet = ValueKey(
    'recog.mathPen.onDeviceSheet',
  );

  /// The bubble tap's question before converting strokes over the ink
  /// limits (the formula keeps no handwriting then).
  static const ValueKey<String> inkTooLargeDialog = ValueKey(
    'recog.mathPen.inkTooLarge',
  );
  static const ValueKey<String> inkTooLargeCancel = ValueKey(
    'recog.mathPen.inkTooLarge.cancel',
  );
  static const ValueKey<String> inkTooLargeConvert = ValueKey(
    'recog.mathPen.inkTooLarge.convert',
  );
}

/// The preview's font size (logical px).
const double kMathPenPreviewFontSize = 20;

class MathPenBubble extends ConsumerWidget {
  const MathPenBubble({
    super.key,
    required this.view,
    required this.onConvert,
    required this.onRetry,
  });

  final MathPenView view;
  final VoidCallback onConvert;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    Widget preview(String latex, {double opacity = 1}) => Opacity(
      opacity: opacity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 56),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: ink.MathPreview(
            key: MathPenBubbleKeys.preview,
            latex: latex,
            fontSize: kMathPenPreviewFontSize,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
    Widget status(String text, {Color? color}) => Text(
      text,
      key: MathPenBubbleKeys.status,
      style: TextStyle(color: color ?? scheme.onSurfaceVariant),
    );

    return switch (view) {
      MathPenIdle() => const SizedBox(width: 44, height: 32),
      MathPenWaiting(:final previous) => Row(
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
            Flexible(child: preview(previous, opacity: 0.4)),
          ],
        ],
      ),
      MathPenAnswer(:final usable, :final result) =>
        usable != null
            ? preview(usable)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.latex,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  status(RecognitionStrings.mathPenUnusable),
                ],
              ),
      MathPenFailed(:final message) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: status(message, color: scheme.error)),
          TextButton(
            key: MathPenBubbleKeys.retry,
            style: kSheetMinTapStyle,
            onPressed: onRetry,
            child: const Text(RecognitionStrings.retry),
          ),
        ],
      ),
      MathPenNeedsConsent() => status(RecognitionStrings.mathPenConsent),
      MathPenNoEngine() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          status(RecognitionStrings.mathPenOff),
          Wrap(
            spacing: 4,
            children: [
              if (ref.watch(mathModelManagerProvider) != null)
                TextButton(
                  key: MathPenBubbleKeys.enableOnDevice,
                  style: kSheetMinTapStyle,
                  onPressed: () => unawaited(_showOnDeviceTile(context)),
                  child: const Text(RecognitionStrings.mathPenEnableOnDevice),
                ),
              TextButton(
                key: MathPenBubbleKeys.typeLatex,
                style: kSheetMinTapStyle,
                onPressed: onConvert,
                child: Text(RecognitionStrings.mathPenTypeLatex, style: muted),
              ),
            ],
          ),
        ],
      ),
    };
  }

  /// Settings' '기기에서 수식 인식' tile in a sheet — the same tile, no new
  /// road to the settings screen. When it closes the group is recognized
  /// again ([onRetry]): the engine may be on now.
  Future<void> _showOnDeviceTile(BuildContext context) async {
    await showRecognitionSheet<void>(
      context,
      sheetKey: MathPenBubbleKeys.onDeviceSheet,
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: OnDeviceMathTile(enabled: true),
        ),
      ),
    );
    onRetry();
  }
}
