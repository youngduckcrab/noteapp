/// Names on hover (UI stage 2, 01-infra 16): a stylus held over the screen
/// (or a mouse) over an icon-only button shows its name — '펜을 띄우면 이름
/// 보기' (settings › 화면, default on).
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Whether names show on hover below — '펜을 띄우면 이름 보기'. The app puts
/// one above its routes from that setting; without one names show.
///
/// It is the one policy for every icon name of the app, so it also sets the
/// [TooltipTheme] below: a plain `IconButton(tooltip: …)` (library, settings)
/// shows its name only on hover, never on a long press (touch), and with
/// [enabled] off not at all — the tooltip stays in semantics (TalkBack reads
/// it), it just never shows. A [Tooltip] that must show on a long press sets
/// its own `triggerMode`.
class HoverNames extends StatelessWidget {
  const HoverNames({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  /// How long a hover waits before a plain tooltip shows while [enabled] is
  /// off: never, in practice.
  static const Duration _never = Duration(days: 1);

  /// [enabled] of the nearest [HoverNames] (true without one).
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HoverNamesScope>()?.enabled ??
      true;

  @override
  Widget build(BuildContext context) {
    final theme = TooltipTheme.of(context);
    return TooltipTheme(
      data: theme.copyWith(
        triggerMode: TooltipTriggerMode.manual,
        waitDuration: enabled ? (theme.waitDuration ?? HoverName.wait) : _never,
      ),
      child: _HoverNamesScope(enabled: enabled, child: child),
    );
  }
}

class _HoverNamesScope extends InheritedWidget {
  const _HoverNamesScope({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_HoverNamesScope oldWidget) =>
      oldWidget.enabled != enabled;
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
    this.enabled = true,
  });

  /// The name shown.
  final String name;

  final Widget child;

  /// Shows the name even while [HoverNames] is off (a style whose tool names
  /// show only on hover — ToolLabelMode.onHover).
  final bool force;

  /// False: no name for now (the button's own menu is open — the name
  /// would sit on top of it).
  final bool enabled;

  /// How long the pointer rests before the name shows.
  static const Duration wait = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context) {
    if (!enabled || (!force && !HoverNames.enabledOf(context))) return child;
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
