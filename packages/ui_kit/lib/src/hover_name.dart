/// Names on hover (UI stage 2, 01-infra 14.7): a stylus held over the screen
/// (or a mouse) over an icon-only button shows its name — '펜을 띄우면 이름
/// 보기' (settings › 화면, default on).
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Whether [HoverName]s below show their names. The app puts one above its
/// routes from the '펜을 띄우면 이름 보기' setting; without one names show.
class HoverNames extends InheritedWidget {
  const HoverNames({super.key, required this.enabled, required super.child});

  final bool enabled;

  /// [enabled] of the nearest [HoverNames] (true without one).
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HoverNames>()?.enabled ?? true;

  @override
  bool updateShouldNotify(HoverNames oldWidget) => oldWidget.enabled != enabled;
}

/// The name of an icon-only control, shown while a hovering stylus or a
/// mouse is over it — never on a touch or a long press (the editor's tool
/// buttons use the long press), and not added to semantics (the control
/// carries its own label).
class HoverName extends StatelessWidget {
  const HoverName({
    super.key,
    required this.name,
    required this.child,
    this.force = false,
  });

  /// The name shown.
  final String name;

  final Widget child;

  /// Shows the name even while [HoverNames] is off (a style whose tool names
  /// show only on hover — ToolLabelMode.onHover).
  final bool force;

  /// How long the pointer rests before the name shows.
  static const Duration wait = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context) {
    if (!force && !HoverNames.enabledOf(context)) return child;
    return Tooltip(
      message: name,
      triggerMode: TooltipTriggerMode.manual,
      excludeFromSemantics: true,
      waitDuration: wait,
      child: child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('name', name));
  }
}
