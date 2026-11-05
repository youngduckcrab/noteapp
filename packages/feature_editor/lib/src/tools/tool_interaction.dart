// lib/src/tools/tool_interaction.dart — 04-editor 6.5.5 / 6.6.
import '../input/input_sample.dart';
import '../input/input_targets.dart';

/// One tool gesture (pen, eraser, lasso, eyedropper or selection transform)
/// driven by the input router from pointer down to up or cancel.
abstract class ToolInteraction {
  ToolInteraction({required this.source, required this.startedAt});
  final InteractionSource source;
  final Duration startedAt;

  /// Screen distance travelled so far (P6 cancel window).
  double get travelled;

  void move(InputSample sample);
  void end(InputSample sample);
  void cancel(); // must leave no trace (no command, overrides cleared)
}
