// m5-7/04-editor 8.2 E2-04a: StylusContact (6.3.2 — contract 7.2.10 E-4) —
// the contact rule × button bits × event type table, and the gesture at
// contact (6.3.3), with synthetic PointerEvents (no binding).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/stylus_contact.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every combination of the three low button bits: 0x01 contact, 0x02 barrel
/// (primary stylus) button, 0x04 secondary stylus button.
const _buttons = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07];
const _kinds = [PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus];

enum _Type { down, move, hover, up, cancel }

PointerEvent _event(_Type type, PointerDeviceKind kind, int buttons) =>
    switch (type) {
      _Type.down => PointerDownEvent(kind: kind, buttons: buttons),
      _Type.move => PointerMoveEvent(kind: kind, buttons: buttons),
      _Type.hover => PointerHoverEvent(kind: kind, buttons: buttons),
      _Type.up => PointerUpEvent(kind: kind, buttons: buttons),
      _Type.cancel => PointerCancelEvent(kind: kind, buttons: buttons),
    };

/// The expected table (6.3.2): native — every down / move is contact; web —
/// a down / move is contact only with bit 0x01; hover / up / cancel never.
bool _expectedContact(StylusContactRule rule, _Type type, int buttons) {
  if (type != _Type.down && type != _Type.move) return false;
  return switch (rule) {
    StylusContactRule.native => true,
    StylusContactRule.web => buttons & 0x01 != 0,
  };
}

/// 6.3.3: the eraser tip wins over the barrel button; bit 0x02 → penButton.
EditorGesture? _expectedGesture(PointerDeviceKind kind, int buttons) {
  if (kind == PointerDeviceKind.invertedStylus) {
    return EditorGesture.invertedStylus;
  }
  return buttons & 0x02 != 0 ? EditorGesture.penButton : null;
}

void main() {
  test('the bits are the Flutter constants (0x01 contact, 0x02 barrel)', () {
    expect(kStylusContact, 0x01);
    expect(kPrimaryStylusButton, 0x02);
    expect(kSecondaryStylusButton, 0x04);
  });

  group('isContact: rule × buttons × event type × kind', () {
    for (final rule in StylusContactRule.values) {
      for (final type in _Type.values) {
        for (final kind in _kinds) {
          for (final buttons in _buttons) {
            final expected = _expectedContact(rule, type, buttons);
            final hex = '0x${buttons.toRadixString(16).padLeft(2, '0')}';
            test('${rule.name} ${type.name} ${kind.name} $hex → $expected', () {
              expect(
                StylusContact.isContact(rule, _event(type, kind, buttons)),
                expected,
              );
            });
          }
        }
      }
    }
  });

  test('named rows of 6.3.2', () {
    const web = StylusContactRule.web;
    const native = StylusContactRule.native;
    const stylus = PointerDeviceKind.stylus;
    // Web: the barrel button above the screen → down 0x02 is airborne …
    expect(
      StylusContact.isContact(
        web,
        const PointerDownEvent(kind: stylus, buttons: 0x02),
      ),
      isFalse,
    );
    // … the touching move 0x03 is the contact …
    expect(
      StylusContact.isContact(
        web,
        const PointerMoveEvent(kind: stylus, buttons: 0x03),
      ),
      isTrue,
    );
    // … and move 0x02 (pen lifted, button held) ends it (E-4 v2.1).
    expect(
      StylusContact.isContact(
        web,
        const PointerMoveEvent(kind: stylus, buttons: 0x02),
      ),
      isFalse,
    );
    // Native (Android engine): a touching pen with the button → down 0x02
    // without the contact bit is still contact.
    expect(
      StylusContact.isContact(
        native,
        const PointerDownEvent(kind: stylus, buttons: 0x02),
      ),
      isTrue,
    );
  });

  group('gestureAtContact: kind × buttons', () {
    for (final kind in _kinds) {
      for (final buttons in _buttons) {
        final expected = _expectedGesture(kind, buttons);
        final hex = '0x${buttons.toRadixString(16).padLeft(2, '0')}';
        test('${kind.name} $hex → ${expected?.name}', () {
          for (final e in [
            PointerDownEvent(kind: kind, buttons: buttons),
            PointerMoveEvent(kind: kind, buttons: buttons),
          ]) {
            expect(StylusContact.gestureAtContact(e), expected);
          }
        });
      }
    }
  });

  test('platformRule: native on the VM; debugRuleOverride wins', () {
    addTearDown(() => StylusContact.debugRuleOverride = null);
    expect(StylusContact.platformRule, StylusContactRule.native);
    StylusContact.debugRuleOverride = StylusContactRule.web;
    expect(StylusContact.platformRule, StylusContactRule.web);
    StylusContact.debugRuleOverride = null;
    expect(StylusContact.platformRule, StylusContactRule.native);
  });
}
