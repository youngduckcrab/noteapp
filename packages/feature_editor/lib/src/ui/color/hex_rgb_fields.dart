// lib/src/ui/color/hex_rgb_fields.dart — 04-editor 6.9.5 (HEX · R/G/B).
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../editor_strings.dart';
import 'color_math.dart';

/// The HEX field and the R / G / B fields of [argb]. A value is applied the
/// moment the input becomes valid; on focus loss or submit an invalid input
/// goes back to the current value. Number fields take digits only (0–255).
/// An 8-digit HEX sets the colour (opaque) and the opacity AA / 255 (at least
/// 0.05).
class HexRgbFields extends StatefulWidget {
  const HexRgbFields({
    super.key,
    required this.argb,
    required this.onColor,
    required this.onOpacity,
  });

  final int argb;
  final ValueChanged<int> onColor;
  final ValueChanged<double> onOpacity;

  static const hexKey = ValueKey('editor.color.hex');
  static const redKey = ValueKey('editor.color.r');
  static const greenKey = ValueKey('editor.color.g');
  static const blueKey = ValueKey('editor.color.b');

  /// Lowest opacity an 8-digit HEX can give (6.9.5).
  static const double minOpacity = 0.05;

  @override
  State<HexRgbFields> createState() => _HexRgbFieldsState();
}

class _HexRgbFieldsState extends State<HexRgbFields> {
  final TextEditingController _hex = TextEditingController();
  final List<TextEditingController> _channels = List.generate(
    3,
    (_) => TextEditingController(),
  );
  final FocusNode _hexFocus = FocusNode(debugLabel: 'editor.color.hex');
  final List<FocusNode> _channelFocus = List.generate(
    3,
    (i) => FocusNode(debugLabel: 'editor.color.channel$i'),
  );

  @override
  void initState() {
    super.initState();
    _sync();
    _hexFocus.addListener(() {
      if (!_hexFocus.hasFocus) _revertHex();
    });
    for (var i = 0; i < 3; i++) {
      final node = _channelFocus[i];
      node.addListener(() {
        if (!node.hasFocus) _revertChannel(i);
      });
    }
  }

  @override
  void didUpdateWidget(HexRgbFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.argb != widget.argb) _sync();
  }

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    for (final c in _channels) {
      c.dispose();
    }
    for (final f in _channelFocus) {
      f.dispose();
    }
    super.dispose();
  }

  List<int> get _rgb {
    final c = ColorMath.toRgb(widget.argb);
    return [c.r, c.g, c.b];
  }

  /// Rewrites the fields that do not already show the current colour (a
  /// field the user is typing a valid value into keeps its text).
  void _sync() {
    final parsed = ColorMath.parseHex(_hex.text);
    if (parsed == null ||
        ColorMath.opaque(parsed) != ColorMath.opaque(widget.argb)) {
      _setText(_hex, ColorMath.toHex(widget.argb));
    }
    final rgb = _rgb;
    for (var i = 0; i < 3; i++) {
      if (int.tryParse(_channels[i].text) != rgb[i]) {
        _setText(_channels[i], '${rgb[i]}');
      }
    }
  }

  static void _setText(TextEditingController c, String text) {
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onHex(String text) {
    final value = ColorMath.parseHex(text);
    if (value == null) return;
    var digits = text.trim();
    if (digits.startsWith('#')) digits = digits.substring(1);
    if (digits.length == 8) {
      widget.onOpacity(
        math.max(HexRgbFields.minOpacity, ColorMath.alphaOf(value)),
      );
    }
    final color = ColorMath.opaque(value);
    if (color != ColorMath.opaque(widget.argb)) widget.onColor(color);
  }

  void _revertHex() {
    final parsed = ColorMath.parseHex(_hex.text);
    if (parsed == null ||
        ColorMath.opaque(parsed) != ColorMath.opaque(widget.argb)) {
      _setText(_hex, ColorMath.toHex(widget.argb));
    }
  }

  void _onChannel(int index, String text) {
    final v = int.tryParse(text);
    if (v == null || v < 0 || v > 255) return;
    final rgb = _rgb;
    if (rgb[index] == v) return;
    rgb[index] = v;
    widget.onColor(ColorMath.fromRgb(rgb[0], rgb[1], rgb[2]));
  }

  void _revertChannel(int index) {
    final current = _rgb[index];
    if (int.tryParse(_channels[index].text) != current) {
      _setText(_channels[index], '$current');
    }
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      HexRgbFields.redKey,
      HexRgbFields.greenKey,
      HexRgbFields.blueKey,
    ];
    const labels = [
      EditorStrings.colorRed,
      EditorStrings.colorGreen,
      EditorStrings.colorBlue,
    ];
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: TextField(
            key: HexRgbFields.hexKey,
            controller: _hex,
            focusNode: _hexFocus,
            decoration: const InputDecoration(
              labelText: EditorStrings.colorHex,
              isDense: true,
              border: OutlineInputBorder(),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F ]')),
              LengthLimitingTextInputFormatter(11),
            ],
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: _onHex,
            onSubmitted: (_) => _revertHex(),
          ),
        ),
        for (var i = 0; i < 3; i++) ...[
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: TextField(
              key: keys[i],
              controller: _channels[i],
              focusNode: _channelFocus[i],
              decoration: InputDecoration(
                labelText: labels[i],
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              textInputAction: TextInputAction.done,
              onChanged: (text) => _onChannel(i, text),
              onSubmitted: (_) => _revertChannel(i),
            ),
          ),
        ],
      ],
    );
  }
}
