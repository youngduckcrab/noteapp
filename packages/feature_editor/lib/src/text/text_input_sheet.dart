// lib/src/text/text_input_sheet.dart — m5-7/04-editor 6.11.6 안 A (E2-01:
// the minimal sheet mode).
//
// The web fallback A: instead of a transformed field over the box, a plain
// multi-line TextField in a panel fixed to the TOP of the editor body (just
// below the toolbar — a bottom sheet would be covered by the iPad keyboard,
// about 40 % of the screen in landscape). While typing, the canvas shows a
// same-id preview of the draft (TextEditNotifier — preview wins over hidden,
// 7.2.9 v2.1). The whole panel is one tap group with the field (a tap on the
// panel or on [완료] is "inside"); a pointer down elsewhere ends the session
// (tapOutside), [완료] ends it with `done`. An EDITOR-own panel, so the 7.4.10
// bottom-sheet rule (other areas' UI) does not apply (00-review 3.4 Q4).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/settings/editor_device_state.dart';
import '../ui/editor_strings.dart';
import 'text_box_editor.dart';
import 'text_edit_session.dart';

/// The top panel of the sheet mode. Nothing outside a sheet-mode session.
class TextInputSheet extends ConsumerWidget {
  const TextInputSheet({super.key});

  static const panelKey = ValueKey('editor.textSheet.panel');
  static const doneKey = ValueKey('editor.textSheet.done');

  /// At most this share of the screen height.
  static const double maxScreenFraction = 0.4;

  /// Room kept between the panel and the keyboard (px).
  static const double keyboardGap = 120;

  /// The panel never gets lower than its title row and one line.
  static const double minHeight = 96;

  /// min(40 % of [screenHeight], [areaHeight] − [insetBottom] − 120), at
  /// least [minHeight] and never more than [areaHeight]. [areaHeight] is the
  /// page area below the toolbar; [insetBottom] the keyboard height this
  /// area still overlaps (0 when the Scaffold already shrank the body for
  /// the keyboard, which then shows in [areaHeight]).
  static double heightFor({
    required double screenHeight,
    required double areaHeight,
    required double insetBottom,
  }) {
    final h = math.min(
      maxScreenFraction * screenHeight,
      areaHeight - insetBottom - keyboardGap,
    );
    return math.min(math.max(h, minHeight), areaHeight);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(editorTextEditProvider);
    if (session == null || session.mode != WebTextInputMode.sheet) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(editorTextEditProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = heightFor(
          screenHeight: screenHeight,
          areaHeight: constraints.maxHeight,
          insetBottom: insetBottom,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: height,
            width: constraints.maxWidth,
            child: TextFieldTapRegion(
              child: Material(
                key: panelKey,
                color: scheme.surfaceContainerHigh,
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              EditorStrings.textInputSheetTitle,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          TextButton(
                            key: doneKey,
                            onPressed: () => unawaited(
                              notifier.end(reason: TextEditEndReason.done),
                            ),
                            child: const Text(EditorStrings.done),
                          ),
                        ],
                      ),
                      Expanded(
                        child: TextSessionField(
                          key: ValueKey('editor.textSheet.${session.boxId}'),
                          initialText: session.draft.text,
                          expands: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
