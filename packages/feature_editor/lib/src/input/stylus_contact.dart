// lib/src/input/stylus_contact.dart — m5-7/04-editor 6.3.2 (contract 7.2.10
// E-4): when a stylus pointer touches the screen, and which gesture starts at
// that contact (6.3.3).
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../state/settings/editor_settings.dart';

/// native: a PointerDownEvent is contact (the pointer stays in contact until
/// up / cancel). web: contact only while buttons & kStylusContact != 0 — a
/// pen held above the screen with the barrel button pressed reports
/// `down(0x02)` before it touches, and lifting it with the button still held
/// reports `move(0x02)` without an up (research 02 8.4).
enum StylusContactRule { native, web }

/// Pure functions, unit-tested with synthetic PointerEvents (no binding).
abstract final class StylusContact {
  /// Tests: the rule a new router uses (null = by platform). Reset in tearDown.
  @visibleForTesting
  static StylusContactRule? debugRuleOverride;

  /// Chosen once per router: kIsWeb ? web : native (7.4.1 — kIsWeb only).
  static StylusContactRule get platformRule =>
      debugRuleOverride ??
      (kIsWeb ? StylusContactRule.web : StylusContactRule.native);

  /// native: a PointerDownEvent (and every move while the pointer is down) is
  /// contact. web: contact only while buttons & kStylusContact != 0. Hover,
  /// up and cancel events are never contact.
  static bool isContact(StylusContactRule rule, PointerEvent e) {
    final pressed = e is PointerDownEvent || e is PointerMoveEvent;
    if (!pressed) return false;
    return switch (rule) {
      StylusContactRule.native => true,
      StylusContactRule.web => e.buttons & kStylusContact != 0,
    };
  }

  /// The gesture that starts at contact: invertedStylus kind → invertedStylus;
  /// buttons & kPrimaryStylusButton != 0 → penButton; else null.
  static EditorGesture? gestureAtContact(PointerEvent e) {
    if (e.kind == PointerDeviceKind.invertedStylus) {
      return EditorGesture.invertedStylus;
    }
    if (e.buttons & kPrimaryStylusButton != 0) return EditorGesture.penButton;
    return null;
  }
}
