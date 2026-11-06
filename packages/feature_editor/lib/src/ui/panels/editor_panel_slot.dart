// lib/src/ui/panels/editor_panel_slot.dart — m5-7/04-editor 6.15.4 (E2-16).
//
// The bottom panel slot: under the page viewport in EditorBody's Column, at
// most 40 % of the body height, clipped. It calls
// EditorExtensions.recordingPanel (media_io's RecordingPanel) with an
// EditorPanelContext built when the panel opens:
//   - tapToSeek: a ValueNotifier<bool> owned here that follows
//     EditorSettings.tapToSeek; setTapToSeek → EditorSettingsNotifier
//     (device key, 500 ms debounce);
//   - close: closes the panel (a recording goes on).
// An exception from the builder call is reported (FlutterError.reportError,
// library 'feature_editor' — E-7) and the slot shows one line
// '녹음 패널을 열지 못했어요' until the panel is closed. An exception while
// building the panel's own widgets is Flutter's ErrorWidget as usual.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../../state/panel.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../editor_strings.dart';

/// The slot is at most this part of the body height.
const double kPanelSlotMaxHeightFraction = 0.4;

class EditorPanelSlot extends ConsumerStatefulWidget {
  const EditorPanelSlot({
    super.key = slotKey,
    required this.builder,
    required this.bodyHeight,
  });

  static const slotKey = ValueKey('editor.panelSlot');

  /// The one line shown when the builder threw.
  static const failedKey = ValueKey('editor.panelSlot.failed');

  final EditorPanelBuilder builder;

  /// The height of EditorBody's Column (the slot takes at most 40 % of it).
  final double bodyHeight;

  @override
  ConsumerState<EditorPanelSlot> createState() => _EditorPanelSlotState();
}

class _EditorPanelSlotState extends ConsumerState<EditorPanelSlot> {
  late final ValueNotifier<bool> _tapToSeek;
  late final EditorPanelContext _panel;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _tapToSeek = ValueNotifier(
      ref.read(editorSettingsProvider.select((s) => s.tapToSeek)),
    );
    _panel = EditorPanelContext(
      noteId: ref.read(editorNoteIdProvider),
      tapToSeek: _tapToSeek,
      setTapToSeek: _setTapToSeek,
      close: _close,
    );
  }

  void _setTapToSeek(bool value) {
    if (!mounted) return;
    ref.read(editorSettingsProvider.notifier).setTapToSeek(value);
  }

  void _close() {
    if (!mounted) return;
    ref.read(editorPanelProvider.notifier).close();
  }

  @override
  void dispose() {
    _tapToSeek.dispose();
    super.dispose();
  }

  Widget _buildPanel(BuildContext context) {
    if (_failed) return const _FailedLine();
    try {
      return widget.builder(context, _panel);
    } on Object catch (error, stack) {
      _failed = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while building the recording panel'),
        ),
      );
      return const _FailedLine();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      editorSettingsProvider.select((s) => s.tapToSeek),
      (_, value) => _tapToSeek.value = value,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.bodyHeight * kPanelSlotMaxHeightFraction,
      ),
      child: ClipRect(child: _buildPanel(context)),
    );
  }
}

class _FailedLine extends StatelessWidget {
  const _FailedLine();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Text(
      EditorStrings.recordingPanelFailed,
      key: EditorPanelSlot.failedKey,
    ),
  );
}

/// The slot when the panel is open and the extension has a builder; else
/// nothing (EditorBody puts it under the page viewport).
class EditorPanelArea extends ConsumerWidget {
  const EditorPanelArea({super.key, required this.bodyHeight});

  final double bodyHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(editorPanelProvider);
    final builder = ref.watch(
      editorExtensionsProvider.select((e) => e.recordingPanel),
    );
    if (!open || builder == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        EditorPanelSlot(builder: builder, bodyHeight: bodyHeight),
      ],
    );
  }
}
