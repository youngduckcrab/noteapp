// lib/src/ui/pickers/page_size_picker.dart — 05-library 6.12: page size
// (A4 · Letter · 16:9 · 사용자 지정 = PageSizePreset.a4 / letter /
// widescreen16x9 / null) with the custom width / height fields in mm, and the
// orientation (세로 · 가로, disabled for a custom size). The only limits are
// CORE's PageSizeLimits, shown in mm through PageSizeMm (contract 7.2.5).
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show PageSizePreset;

import '../../l10n/library_strings.dart';
import '../../model/new_note_spec.dart';
import '../../model/page_size_mm.dart';

enum _SizeChoice { a4, letter, widescreen16x9, custom }

_SizeChoice _choiceOf(PageSizePreset? preset) => switch (preset) {
  PageSizePreset.a4 => _SizeChoice.a4,
  PageSizePreset.letter => _SizeChoice.letter,
  PageSizePreset.widescreen16x9 => _SizeChoice.widescreen16x9,
  null => _SizeChoice.custom,
};

/// [value]'s size, orientation and custom mm. Valid choices are reported
/// through [onChanged]; [onValidityChanged] tells whether both custom fields
/// hold an accepted number (always true for a preset).
class PageSizePicker extends StatefulWidget {
  const PageSizePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.onValidityChanged,
  });

  final NewNoteOptions value;
  final ValueChanged<NewNoteOptions> onChanged;
  final ValueChanged<bool>? onValidityChanged;

  /// One decimal, as the fields show it.
  static String formatMm(double mm) => mm.toStringAsFixed(1);

  /// Text of a custom size field → mm, or null when it is not a number
  /// inside PageSizeMm.minInputMm..maxInputMm.
  static double? parseMm(String text) {
    final mm = double.tryParse(text.trim());
    if (mm == null || !PageSizeMm.isValidInput(mm)) return null;
    return mm;
  }

  /// The custom field start value for a pt side: rounded to 0.1 mm, then
  /// clamped into the input range.
  static double startMm(double pt) =>
      PageSizeMm.clampInput((PageSizeMm.toMm(pt) * 10).round() / 10);

  @override
  State<PageSizePicker> createState() => _PageSizePickerState();
}

class _PageSizePickerState extends State<PageSizePicker> {
  late final TextEditingController _width = TextEditingController(
    text: PageSizePicker.formatMm(widget.value.customWidthMm),
  );
  late final TextEditingController _height = TextEditingController(
    text: PageSizePicker.formatMm(widget.value.customHeightMm),
  );
  bool _lastValid = true;

  bool get _widthOk => PageSizePicker.parseMm(_width.text) != null;
  bool get _heightOk => PageSizePicker.parseMm(_height.text) != null;

  @override
  void didUpdateWidget(PageSizePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A custom size changed from outside (e.g. another device's defaults):
    // show it unless the field already says the same.
    _sync(_width, oldWidget.value.customWidthMm, widget.value.customWidthMm);
    _sync(_height, oldWidget.value.customHeightMm, widget.value.customHeightMm);
  }

  void _sync(TextEditingController field, double before, double now) {
    if (before == now || PageSizePicker.parseMm(field.text) == now) return;
    field.text = PageSizePicker.formatMm(now);
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _select(_SizeChoice choice) {
    final value = widget.value;
    final NewNoteOptions next;
    switch (choice) {
      case _SizeChoice.custom:
        if (value.isCustom) return;
        // Start from the size chosen so far (0.1 mm, inside the range).
        final size = value.pageSize;
        final w = PageSizePicker.startMm(size.width);
        final h = PageSizePicker.startMm(size.height);
        _width.text = PageSizePicker.formatMm(w);
        _height.text = PageSizePicker.formatMm(h);
        next = value.copyWith(
          custom: true,
          customWidthMm: w,
          customHeightMm: h,
        );
      case _SizeChoice.a4:
      case _SizeChoice.letter:
      case _SizeChoice.widescreen16x9:
        final preset = switch (choice) {
          _SizeChoice.a4 => PageSizePreset.a4,
          _SizeChoice.letter => PageSizePreset.letter,
          _ => PageSizePreset.widescreen16x9,
        };
        next = value.copyWith(
          preset: preset,
          // 16:9 is a screen format: landscape first (the user can switch).
          orientation: preset == PageSizePreset.widescreen16x9
              ? PageOrientationChoice.landscape
              : null,
        );
    }
    widget.onChanged(next);
    _lastValid = true;
    widget.onValidityChanged?.call(true);
  }

  void _fieldChanged() {
    setState(() {}); // error text
    final w = PageSizePicker.parseMm(_width.text);
    final h = PageSizePicker.parseMm(_height.text);
    if (w != null && h != null) {
      widget.onChanged(
        widget.value.copyWith(
          custom: true,
          customWidthMm: w,
          customHeightMm: h,
        ),
      );
    }
    // Report after onChanged so the parent's value is custom already.
    final valid = w != null && h != null;
    if (valid != _lastValid) {
      _lastValid = valid;
      widget.onValidityChanged?.call(valid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final custom = value.isCustom;
    final rangeText = LibraryStrings.customSizeRange(
      PageSizeMm.minInputMm,
      PageSizeMm.maxInputMm,
    );
    Widget field(TextEditingController controller, String label, bool ok) =>
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}(\.\d?)?$')),
            ],
            decoration: InputDecoration(
              labelText: label,
              suffixText: LibraryStrings.millimeters,
              errorText: ok ? null : rangeText,
              errorMaxLines: 2,
            ),
            onChanged: (_) => _fieldChanged(),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_SizeChoice>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _SizeChoice.a4,
                label: Text(LibraryStrings.pageSizeA4),
              ),
              ButtonSegment(
                value: _SizeChoice.letter,
                label: Text(LibraryStrings.pageSizeLetter),
              ),
              ButtonSegment(
                value: _SizeChoice.widescreen16x9,
                label: Text(LibraryStrings.pageSize16x9),
              ),
              ButtonSegment(
                value: _SizeChoice.custom,
                label: Text(LibraryStrings.pageSizeCustom),
              ),
            ],
            selected: {_choiceOf(value.preset)},
            onSelectionChanged: (s) => _select(s.single),
          ),
        ),
        if (custom) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field(_width, LibraryStrings.customWidth, _widthOk),
              const SizedBox(width: 12),
              field(_height, LibraryStrings.customHeight, _heightOk),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(
          LibraryStrings.fieldOrientation,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SegmentedButton<PageOrientationChoice>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: PageOrientationChoice.portrait,
              label: Text(LibraryStrings.portrait),
              icon: Icon(Icons.crop_portrait),
            ),
            ButtonSegment(
              value: PageOrientationChoice.landscape,
              label: Text(LibraryStrings.landscape),
              icon: Icon(Icons.crop_landscape),
            ),
          ],
          selected: {value.orientation},
          // A custom size is typed as width × height: no orientation.
          onSelectionChanged: custom
              ? null
              : (s) => widget.onChanged(value.copyWith(orientation: s.single)),
        ),
      ],
    );
  }
}
