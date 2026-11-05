// lib/src/ui/pickers/template_picker.dart — 05-library 6.12: 7 cells —
// blank page + the 6 PageTemplateKind values (INK draws all 6, contract 7.8).
// Each cell = TemplatePictogram (48 × 64) + name, at least 44 × 44.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show PageTemplateKind;

import '../../l10n/library_strings.dart';
import 'template_pictogram.dart';

class TemplatePicker extends StatelessWidget {
  const TemplatePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// null = blank page.
  final PageTemplateKind? value;
  final ValueChanged<PageTemplateKind?> onChanged;

  /// Display order: blank page, then PageTemplateKind.values.
  static const List<PageTemplateKind?> choices = [
    null,
    ...PageTemplateKind.values,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final kind in choices)
          _TemplateCell(
            kind: kind,
            selected: kind == value,
            onTap: () => onChanged(kind),
          ),
      ],
    );
  }
}

class _TemplateCell extends StatelessWidget {
  const _TemplateCell({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final PageTemplateKind? kind;
  final bool selected;
  final VoidCallback onTap;

  static const double ring = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = LibraryStrings.templateName(kind);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: TemplatePictogram.size.width + 2 * (ring + 2) + 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.fromBorderSide(
                      selected
                          ? BorderSide(
                              color: theme.colorScheme.primary,
                              width: ring,
                            )
                          : BorderSide.none,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(ring + 2),
                    child: TemplatePictogram(kind: kind),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
