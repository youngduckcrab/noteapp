// Shared body: decoding JSON written by the web build, where real numbers without a
// fraction arrive as integers (jsonEncode(1.0) == '1' in dart2js, CORE 6.3 / 7.4.6).
// Run on the VM (test/model/json_web_format_test.dart) and in Chrome
// (test/web/json_web_format_browser_test.dart).
import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void defineJsonWebFormatTests() {
  test('stroke style with integer reals', () {
    final json = jsonDecode(
      '{"id":"s1","pageId":"p1","style":{"tool":"marker","color":4280427042,"width":5,'
      '"opacity":1,"pressureSensitivity":1,"pressureCurve":[0,0,1,1],"smoothing":1,'
      '"extras":{}},"points":"AQED0A9klgGgHzIA9AMyMgBUUg==","recordingId":null,'
      '"recordingOffsetMs":null,"createdAt":1793750400000,"updatedAt":1793750400000,'
      '"deletedAt":null,"version":"001793750400000-0000-3f2a9c0d11e0b7a4"}',
    ) as Map<String, Object?>;
    final s = Stroke.fromJson(json);
    expect(s.style.width, 5.0);
    expect(s.style.opacity, 1.0);
    expect(s.style.smoothing, 1.0);
    expect(
      s.style.pressureCurve,
      const PressureCurve(x1: 0, y1: 0, x2: 1, y2: 1),
    );
    expect(s.points.length, 3);
    expect(s.createdAt, 1793750400000);
  });

  test('page size and template with integer reals', () {
    final json = jsonDecode(
      '{"id":"p1","noteId":"n1","sortKey":"a0","size":[960,540],'
      '"background":{"type":"template","paperColor":4294967295,'
      '"template":{"kind":"grid","spacing":20,"lineColor":null,"lineWidth":1,"extras":{}}},'
      '"createdAt":1,"updatedAt":2,"deletedAt":null,"version":null}',
    ) as Map<String, Object?>;
    final p = Page.fromJson(json);
    expect(p.size, PageSize.widescreen16x9);
    final bg = p.background as TemplateBackground;
    expect(bg.template.spacing, 20.0);
    expect(bg.template.lineWidth, 1.0);
  });

  test('geometry, curves and field versions', () {
    expect(
      PageRect.fromJson(
        jsonDecode('{"l":0,"t":1,"r":2,"b":3}') as Map<String, Object?>,
      ),
      const PageRect(0, 1, 2, 3),
    );
    expect(
      Affine2.fromJson(jsonDecode('[1,0,0,1,5,6]') as List<Object?>),
      Affine2.translation(5, 6),
    );
    expect(
      PressureCurve.fromJson(jsonDecode('[0,1,1,0]') as List<Object?>).x1,
      0.0,
    );
    final v = EntityFieldVersions.fromJson(
      jsonDecode('{"b":"001793750400000-0000-3f2a9c0d11e0b7a4"}')
          as Map<String, Object?>,
    );
    expect(v.max.millis, 1793750400000);
  });

  test('settings decode integer reals', () {
    final key = SettingKey.number('editor.width', 1.5);
    expect(SettingsSnapshot({'editor.width': jsonDecode('2')}).get(key), 2.0);
    final map = SettingKey.jsonMap('editor.palette');
    expect(
      SettingsSnapshot({'editor.palette': jsonDecode('{"a":1}')}).get(map),
      {'a': 1},
    );
  });

  test('round trip through jsonEncode on this platform', () {
    final style = StrokeStyle.defaultsFor(PenTool.highlighter);
    final again = StrokeStyle.fromJson(
      jsonDecode(jsonEncode(style.toJson())) as Map<String, Object?>,
    );
    expect(again, style);
  });
}
