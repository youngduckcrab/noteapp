// lib/src/ui/pen/width_slider.dart — 04-editor 6.9.3 #2, 6.9.4.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'width_mapping.dart';

/// "굵기 2.4 pt" · [−] slider [+] for the current pen. The slider is
/// non-linear (WidthMapping); [−] / [+] step 0.1 pt and repeat every 80 ms
/// after a 400 ms hold; tapping the label opens a number field (0.1–30,
/// applied on submit or focus loss, anything else is dropped).
class WidthSlider extends ConsumerStatefulWidget {
  const WidthSlider({super.key});

  static const labelKey = ValueKey('editor.pen.width.label');
  static const inputKey = ValueKey('editor.pen.width.input');
  static const sliderKey = ValueKey('editor.pen.width.slider');
  static const minusKey = ValueKey('editor.pen.width.minus');
  static const plusKey = ValueKey('editor.pen.width.plus');

  /// Hold delay and repeat period of [−] / [+] (6.9.3 #2).
  static const Duration repeatDelay = Duration(milliseconds: 400);
  static const Duration repeatPeriod = Duration(milliseconds: 80);

  @override
  ConsumerState<WidthSlider> createState() => _WidthSliderState();
}

class _WidthSliderState extends ConsumerState<WidthSlider> {
  bool _editing = false;
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'editor.pen.width.input');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commitInput();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  double get _width => ref.read(editorToolProvider).currentPen.width;

  void _set(double width) =>
      ref.read(editorToolProvider.notifier).setWidth(width);

  void _step(double delta) => _set(_width + delta);

  void _startEditing() {
    final text = _width.toStringAsFixed(1);
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    setState(() => _editing = true);
  }

  void _commitInput() {
    final value = double.tryParse(_input.text.trim());
    if (value != null &&
        value >= WidthMapping.min &&
        value <= WidthMapping.max) {
      _set(value);
    }
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final width = ref.watch(
      editorToolProvider.select((s) => s.currentPen.width),
    );
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: _editing
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 120,
                    child: TextField(
                      key: WidthSlider.inputKey,
                      controller: _input,
                      focusNode: _focus,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        LengthLimitingTextInputFormatter(5),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: 'pt',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _commitInput(),
                      // A touch anywhere else ends the input (also on iPad,
                      // where a touch outside keeps the focus by default).
                      onTapOutside: (_) => _focus.unfocus(),
                    ),
                  ),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: WidthSlider.labelKey,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    onPressed: _startEditing,
                    child: Text(
                      EditorStrings.widthLabel(width),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
        ),
        Row(
          children: [
            RepeatButton(
              key: WidthSlider.minusKey,
              icon: Icons.remove,
              semanticLabel: EditorStrings.widthDecrease,
              enabled: width > WidthMapping.min,
              onStep: () => _step(-WidthMapping.step),
            ),
            Expanded(
              child: Semantics(
                label: EditorStrings.width,
                child: Slider(
                  key: WidthSlider.sliderKey,
                  value: WidthMapping.positionOf(width),
                  onChanged: (t) => _set(WidthMapping.widthAt(t)),
                ),
              ),
            ),
            RepeatButton(
              key: WidthSlider.plusKey,
              icon: Icons.add,
              semanticLabel: EditorStrings.widthIncrease,
              enabled: width < WidthMapping.max,
              onStep: () => _step(WidthMapping.step),
            ),
          ],
        ),
      ],
    );
  }
}

/// A 44 × 44 icon button: a tap = one [onStep]; holding it past
/// WidthSlider.repeatDelay steps once and then every
/// WidthSlider.repeatPeriod until it is released.
class RepeatButton extends StatefulWidget {
  const RepeatButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onStep,
    this.enabled = true,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onStep;
  final bool enabled;

  @override
  State<RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<RepeatButton> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void didUpdateWidget(RepeatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: enabled
            ? {
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                      TapGestureRecognizer.new,
                      (r) => r.onTap = widget.onStep,
                    ),
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      LongPressGestureRecognizer
                    >(
                      () => LongPressGestureRecognizer(
                        duration: WidthSlider.repeatDelay,
                      ),
                      (r) => r
                        ..onLongPressStart = (_) {
                          widget.onStep();
                          _stop();
                          _repeat = Timer.periodic(
                            WidthSlider.repeatPeriod,
                            (_) => widget.onStep(),
                          );
                        }
                        ..onLongPressEnd = ((_) => _stop())
                        ..onLongPressCancel = _stop,
                    ),
              }
            : const {},
        child: SizedBox.square(
          dimension: 44,
          child: Icon(
            widget.icon,
            color: enabled
                ? scheme.onSurfaceVariant
                : scheme.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }
}
