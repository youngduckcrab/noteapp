// lib/src/ui/settings/gesture_action_tile.dart — m5-7/04-editor 6.4.4
// (E2-05): the editable gesture rows of the input settings section.
//
// Each row shows a gesture and its action (GestureSettings.actionFor); a tap
// opens a bottom sheet with the actions allowedFor that gesture (radio).
// Picking one writes gestures.withAction(g, a) (editor.settings.synced, the
// 1st-round 500 ms debounce).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../di/stylus_extras.dart';
import '../../state/settings/editor_device_state.dart';
import '../../state/settings/editor_settings.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../editor_strings.dart';

/// The gesture rows (6.4.4 table): the three finger gestures and the pen
/// side button always; the eraser tip when not on the web (the web engine
/// never reports invertedStylus); the Apple Pencil double tap when the
/// pencil source can, the squeeze when it can **and** a squeeze event came
/// on this device (EditorDeviceState.seenSqueeze — CD2-24).
class GestureActionTiles extends ConsumerWidget {
  const GestureActionTiles({super.key});

  /// Tests: pretend to run on the web (null = kIsWeb).
  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get isWeb => debugIsWebOverride ?? kIsWeb;

  /// Appendix C: `editor.settings.gesture.<EditorGesture.name>`.
  static ValueKey<String> rowKey(EditorGesture gesture) =>
      ValueKey('editor.settings.gesture.${gesture.name}');

  /// A choice in the action sheet.
  static ValueKey<String> optionKey(EditorAction action) =>
      ValueKey('editor.settings.gestureSheet.${action.name}');

  static const sheetKey = ValueKey('editor.settings.gestureSheet');
  static const pencilHintKey = ValueKey('editor.settings.gesture.pencilHint');

  /// The rows shown, in table order.
  static List<EditorGesture> visibleGestures({
    required bool isWeb,
    required StylusCapabilities capabilities,
    required bool seenSqueeze,
  }) => [
    EditorGesture.twoFingerTap,
    EditorGesture.threeFingerTap,
    EditorGesture.fingerLongPress,
    EditorGesture.penButton,
    if (!isWeb) EditorGesture.invertedStylus,
    if (capabilities.doubleTap) EditorGesture.pencilDoubleTap,
    if (capabilities.squeeze && seenSqueeze) EditorGesture.pencilSqueeze,
  ];

  static String gestureName(EditorGesture gesture) => switch (gesture) {
    EditorGesture.twoFingerTap => EditorStrings.gestureTwoFingerTap,
    EditorGesture.threeFingerTap => EditorStrings.gestureThreeFingerTap,
    EditorGesture.fingerLongPress => EditorStrings.gestureFingerLongPress,
    EditorGesture.penButton => EditorStrings.gesturePenButton,
    EditorGesture.invertedStylus => EditorStrings.gestureInvertedStylus,
    EditorGesture.pencilDoubleTap => EditorStrings.gesturePencilDoubleTap,
    EditorGesture.pencilSqueeze => EditorStrings.gesturePencilSqueeze,
  };

  static String? gestureHint(EditorGesture gesture) => switch (gesture) {
    EditorGesture.penButton => EditorStrings.gesturePenButtonHint,
    EditorGesture.invertedStylus => EditorStrings.gestureInvertedStylusHint,
    _ => null,
  };

  static String actionName(EditorAction action) => switch (action) {
    EditorAction.none => EditorStrings.actionNone,
    EditorAction.undo => EditorStrings.actionUndo,
    EditorAction.redo => EditorStrings.actionRedo,
    EditorAction.contextMenu => EditorStrings.actionContextMenu,
    EditorAction.eraserWhileHeld => EditorStrings.actionEraserWhileHeld,
    EditorAction.lassoWhileHeld => EditorStrings.actionLassoWhileHeld,
    EditorAction.toggleEraser => EditorStrings.actionToggleEraser,
    EditorAction.previousTool => EditorStrings.actionPreviousTool,
    EditorAction.toolPalette => EditorStrings.actionToolPalette,
    EditorAction.colorPalette => EditorStrings.actionColorPalette,
    EditorAction.followSystem => EditorStrings.actionFollowSystem,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gestures = ref.watch(
      editorSettingsProvider.select((s) => s.gestures),
    );
    final capabilities = ref.watch(stylusExtrasProvider).capabilities;
    final seenSqueeze = ref.watch(
      editorDeviceStateProvider.select((s) => s.seenSqueeze),
    );
    final rows = visibleGestures(
      isWeb: isWeb,
      capabilities: capabilities,
      seenSqueeze: seenSqueeze,
    );
    final pencil = rows.any(
      (g) =>
          g == EditorGesture.pencilDoubleTap ||
          g == EditorGesture.pencilSqueeze,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in rows)
          GestureActionTile(
            key: rowKey(g),
            gesture: g,
            action: gestures.actionFor(g),
            onTap: () => _pick(context, ref, g),
          ),
        if (pencil)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              EditorStrings.pencilNextLaunch,
              key: pencilHintKey,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    EditorGesture gesture,
  ) async {
    final current = ref
        .read(editorSettingsProvider)
        .gestures
        .actionFor(gesture);
    final picked = await showModalBottomSheet<EditorAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) =>
          _ActionSheet(gesture: gesture, current: current),
    );
    if (picked == null || picked == current || !context.mounted) return;
    final notifier = ref.read(editorSettingsProvider.notifier);
    notifier.setGestures(
      ref.read(editorSettingsProvider).gestures.withAction(gesture, picked),
    );
  }
}

/// One gesture row: the gesture, its action and (pen button, eraser tip) the
/// hint about the pens it works with.
class GestureActionTile extends StatelessWidget {
  const GestureActionTile({
    super.key,
    required this.gesture,
    required this.action,
    required this.onTap,
  });

  final EditorGesture gesture;
  final EditorAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = GestureActionTiles.gestureHint(gesture);
    return ListTile(
      title: Text(GestureActionTiles.gestureName(gesture)),
      subtitle: hint == null
          ? null
          : Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Text(
        GestureActionTiles.actionName(action),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// The actions [gesture] may take (allowedFor, table order), the current one
/// checked; a tap closes the sheet with it.
class _ActionSheet extends StatelessWidget {
  const _ActionSheet({required this.gesture, required this.current});

  final EditorGesture gesture;
  final EditorAction current;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      key: GestureActionTiles.sheetKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              GestureActionTiles.gestureName(gesture),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          RadioGroup<EditorAction>(
            groupValue: current,
            onChanged: (a) {
              if (a != null) Navigator.of(context).pop(a);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in GestureSettings.allowedFor(gesture))
                  RadioListTile<EditorAction>(
                    key: GestureActionTiles.optionKey(a),
                    value: a,
                    title: Text(GestureActionTiles.actionName(a)),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
