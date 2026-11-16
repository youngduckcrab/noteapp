// The icon table and names on hover (UI stage 2, 01-infra 14.7).
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

/// How many pixels [kind]'s line art covers on a 24 px canvas.
Future<int> _inkedPixels(AppIconKind kind) async {
  final recorder = ui.PictureRecorder();
  AppIconPainter(
    kind,
    color: const Color(0xFF000000),
  ).paint(Canvas(recorder), const Size(24, 24));
  final image = await recorder.endRecording().toImage(24, 24);
  final data = (await image.toByteData())!;
  var count = 0;
  for (var i = 3; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i) > 0) count++;
  }
  return count;
}

void main() {
  test('every kind has a Material Rounded glyph of the Material font', () {
    for (final kind in AppIconKind.values) {
      expect(kind.material.fontFamily, 'MaterialIcons', reason: kind.name);
    }
  });

  test('one meaning = one icon: no two kinds share a Material glyph', () {
    final seen = <int, AppIconKind>{};
    for (final kind in AppIconKind.values) {
      final other = seen[kind.material.codePoint];
      expect(other, isNull, reason: '${kind.name} = ${other?.name}');
      seen[kind.material.codePoint] = kind;
    }
  });

  test('the line icons of the often-seen screens all draw', () async {
    final lineArt = AppIconKind.values.where((k) => k.hasLineArt).toList();
    expect(lineArt.length, greaterThanOrEqualTo(30));
    for (final kind in lineArt) {
      expect(await _inkedPixels(kind), greaterThan(20), reason: kind.name);
    }
    // A menu-only kind has no line art: the painter draws nothing.
    expect(await _inkedPixels(AppIconKind.rename), 0);
  });

  testWidgets('AppIcon: IconTheme colour and size, style stroke', (
    tester,
  ) async {
    final theme = buildStyleTheme(AppStyle.calm, Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const IconTheme(
          data: IconThemeData(color: Color(0xFF123456), size: 30),
          child: Center(
            child: AppIcon(AppIconKind.search, semanticLabel: '찾기'),
          ),
        ),
      ),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AppIcon),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.painter! as AppIconPainter;
    expect(painter.color, const Color(0xFF123456));
    expect(
      painter.strokeWidth,
      theme.extension<StyleTokens>()!.iconStrokeWidth,
    );
    expect(tester.getSize(find.byType(AppIcon)), const Size(30, 30));
    expect(find.bySemanticsLabel('찾기'), findsOneWidget);
  });

  testWidgets('AppIcon of a menu-only kind is its Material glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppIcon(AppIconKind.duplicate)),
    );
    expect(find.byIcon(AppIconKind.duplicate.material), findsOneWidget);
  });

  group('HoverName', () {
    Future<void> pump(WidgetTester tester, {bool? enabled}) async {
      const button = HoverName(
        name: '올가미',
        child: SizedBox(
          width: 48,
          height: 48,
          child: ColoredBox(color: Color(0xFF888888)),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: enabled == null
                ? button
                : HoverNames(enabled: enabled, child: button),
          ),
        ),
      );
    }

    Future<void> hover(WidgetTester tester, PointerDeviceKind kind) async {
      final gesture = await tester.createGesture(kind: kind);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(HoverName)));
      await tester.pump(HoverName.wait + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('a hovering stylus shows the name (default on)', (
      tester,
    ) async {
      await pump(tester);
      await hover(tester, PointerDeviceKind.stylus);
      expect(find.text('올가미'), findsOneWidget);
    });

    testWidgets('off: no name', (tester) async {
      await pump(tester, enabled: false);
      await hover(tester, PointerDeviceKind.stylus);
      expect(find.text('올가미'), findsNothing);
    });

    testWidgets('enabled: false (its menu is open): no name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: HoverName(
              name: '더보기',
              enabled: false,
              child: SizedBox.square(dimension: 48),
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.stylus,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(HoverName)));
      await tester.pump(HoverName.wait + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('더보기'), findsNothing);
    });

    testWidgets('a long press shows no name (the tools use it)', (
      tester,
    ) async {
      await pump(tester);
      await tester.longPress(find.byType(HoverName));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('올가미'), findsNothing);
    });
  });

  testWidgets('AppIcon keeps its size in a box forced larger', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 48,
            child: AppIcon(AppIconKind.search, size: 20),
          ),
        ),
      ),
    );
    final paint = find.descendant(
      of: find.byType(AppIcon),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(paint), const Size(20, 20));
  });

  group('HoverNames: a plain IconButton tooltip follows the setting', () {
    Future<void> pump(WidgetTester tester, {required bool enabled}) =>
        tester.pumpWidget(
          MaterialApp(
            home: HoverNames(
              enabled: enabled,
              child: Center(
                child: IconButton(
                  tooltip: '정렬',
                  onPressed: () {},
                  icon: const AppIcon(AppIconKind.sort),
                ),
              ),
            ),
          ),
        );

    Future<void> hover(WidgetTester tester) async {
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.stylus,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(IconButton)));
      await tester.pump(HoverName.wait + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('on: shows on hover, not on a long press', (tester) async {
      await pump(tester, enabled: true);
      await tester.longPress(find.byType(IconButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('정렬'), findsNothing);
      await hover(tester);
      expect(find.text('정렬'), findsOneWidget);
    });

    testWidgets('off: never shows; TalkBack still reads it', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, enabled: false);
      await hover(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('정렬'), findsNothing);
      expect(tester.getSemantics(find.byType(IconButton)).tooltip, '정렬');
      semantics.dispose();
    });
  });

  testWidgets('AppIcon follows the IconTheme opacity, like Icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IconTheme(
          data: IconThemeData(color: Color(0xFF000000), opacity: 0.5),
          child: Center(child: AppIcon(AppIconKind.search)),
        ),
      ),
    );
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(AppIcon),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as AppIconPainter;
    expect(painter.color.a, closeTo(0.5, 0.01));
  });
}
