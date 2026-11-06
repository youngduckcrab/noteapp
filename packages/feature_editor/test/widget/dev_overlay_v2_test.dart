// m5-7/04-editor 8.2 E2-20 (part 2), 6.20: the developer overlay's 2nd-round
// lines through the editor (fake CORE, R2-B3 INK) — the pointer line's
// buttons in hex, the contact rule (native / web) and '공중' for a stylus
// event that is not a contact (A-2, E-4); the hover source
// (flutter(<kind>) — B-12); the [녹음] line: the recorder's phase, the last
// stroke's recordingOffsetMs, the player's phase and position (A-5, B-8);
// the current page's objects against the limit (6.22).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/stylus_contact.dart';
import 'package:feature_editor/src/ui/dev/dev_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

const _devOn = EditorSettings(showDevOverlay: true);

String _overlayText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(DevOverlay.overlayKey),
        matching: find.byType(Text),
      ),
    )
    .data!;

/// Long enough for DevMetrics (≤ 4 Hz) and the overlay (250 ms) to show a
/// change.
Future<void> _shown(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() => StylusContact.debugRuleOverride = null);

  test('buttonsHex: at least 2 hex digits', () {
    expect(buttonsHex(0), '0x00');
    expect(buttonsHex(kPrimaryStylusButton), '0x02');
    expect(buttonsHex(kPrimaryButton | kPrimaryStylusButton), '0x03');
    expect(buttonsHex(0x1ff), '0x1ff');
  });

  testWidgets('native: a touching pen shows its buttons and rule, no 공중; '
      'the barrel button → 0x02', (tester) async {
    StylusContact.debugRuleOverride = StylusContactRule.native;
    final h = await pumpEditor(tester, settings: _devOn);
    final at = h.toGlobal(0, const Offset(200, 200));
    await h.driver.down(1, at, kind: PointerDeviceKind.stylus);
    await h.driver.move(1, at + const Offset(30, 10));
    await _shown(tester);
    var text = _overlayText(tester);
    expect(text, contains('포인터 1 (stylus)  buttons 0x01  규칙 native  팜'));
    expect(text, isNot(contains('공중')));
    await h.driver.up(1);
    await _shown(tester);

    await h.driver.down(
      2,
      at + const Offset(0, 60),
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryStylusButton,
    );
    await h.driver.move(2, at + const Offset(30, 70));
    await _shown(tester);
    text = _overlayText(tester);
    expect(text, contains('buttons 0x02  규칙 native  팜'));
    await h.driver.up(2);
    await _shown(tester);
  });

  testWidgets('web: a pen held above the screen with the barrel button → '
      'buttons 0x02, rule web, 공중; touching → 0x03, no 공중', (tester) async {
    StylusContact.debugRuleOverride = StylusContactRule.web;
    final h = await pumpEditor(tester, settings: _devOn);
    final at = h.toGlobal(0, const Offset(200, 300));
    await h.driver.down(
      1,
      at,
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryStylusButton,
    );
    await _shown(tester);
    var text = _overlayText(tester);
    expect(text, contains('buttons 0x02  규칙 web  공중  팜'));
    await h.driver.move(
      1,
      at + const Offset(20, 0),
      buttons: kPrimaryButton | kPrimaryStylusButton,
    );
    await _shown(tester);
    text = _overlayText(tester);
    expect(text, contains('buttons 0x03  규칙 web  팜'));
    expect(text, isNot(contains('공중')));
    await h.driver.up(1);
    await _shown(tester);
  });

  testWidgets('hover source: a stylus hover → flutter(stylus), a mouse '
      '→ flutter(mouse)', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await _shown(tester);
    expect(_overlayText(tester), contains('호버 출처 -'));
    await h.driver.hover(h.toGlobal(0, const Offset(150, 150)));
    await _shown(tester);
    expect(_overlayText(tester), contains('호버 출처 flutter(stylus)'));
    await h.driver.hover(
      h.toGlobal(0, const Offset(160, 150)),
      kind: PointerDeviceKind.mouse,
      pointer: 42,
    );
    await _shown(tester);
    expect(_overlayText(tester), contains('호버 출처 flutter(mouse)'));
  });

  testWidgets('[녹음]: idle → recording; the last stroke offset; the '
      'player phase and position', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn, fakeAudio: true);
    await _shown(tester);
    var text = _overlayText(tester);
    expect(text, contains('[녹음] idle  마지막 획 offset -  재생 idle 0ms'));

    final recorder = h.audioRecorder!;
    await recorder.start(recordingId: 'rec-1', noteId: h.session.noteId);
    recorder.advance(const Duration(milliseconds: 1200));
    await h.driver.stylusStroke([
      for (var i = 0; i < 6; i++) h.toGlobal(0, Offset(120.0 + i * 20, 400)),
    ]);
    await _shown(tester);
    text = _overlayText(tester);
    expect(text, contains('[녹음] recording  마지막 획 offset 1200ms'));

    final playback = h.audioPlayback!;
    await playback.open(
      const core.Recording(
        id: 'rec-0',
        noteId: 'other',
        assetId: 'a',
        durationMs: 60000,
        startedAt: 0,
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    await playback.play();
    playback.setPositionMs(3400);
    // The next stroke rebuilds the overlay with the player's values.
    await h.driver.stylusStroke([
      for (var i = 0; i < 6; i++) h.toGlobal(0, Offset(120.0 + i * 20, 450)),
    ]);
    await _shown(tester);
    text = _overlayText(tester);
    expect(text, contains('재생 playing 3400ms'));
    await recorder.stop();
    await tester.pump();
  });

  testWidgets('objects: the current page objects against the limit', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      settings: _devOn,
      objectsByPageIndex: {
        0: [
          PageObjectFixtures.shape(pageId: 'x', id: 'o-1'),
          PageObjectFixtures.textBox(pageId: 'x', id: 'o-2'),
          PageObjectFixtures.shape(
            pageId: 'x',
            id: 'o-3',
            kind: core.ShapeKind.ellipse,
          ),
        ],
      },
    );
    await _shown(tester);
    expect(
      _overlayText(tester),
      contains('객체 3 / ${core.PageObjectLimits.maxObjectsPerPage}'),
    );
  });
}
