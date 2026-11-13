// Page object JSON (m5-7/02-core 6.2.6 table, 6.3, C-12): the reading rules for known and
// unknown types, unknown enum names (CP-6), always-written keys, no normalization on read,
// UnknownObject key preservation and referencedAssets. Web-safe.
import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';

Map<String, Object?> _json(String name) => kSampleObjects[name]!.toJson();

Map<String, Object?> _with(Map<String, Object?> m, String key, Object? value) =>
    {...m, key: value};

Map<String, Object?> _without(Map<String, Object?> m, String key) =>
    Map.of(m)..remove(key);

Map<String, Object?> _withStyle(
  Map<String, Object?> m,
  String key,
  Object? value,
) => {
  ...m,
  'style': {...(m['style']! as Map<String, Object?>), key: value},
};

void main() {
  group('6.2.6 reading rules', () {
    test('a known type with a readable body is that type', () {
      final types = <String, Type>{
        'shape_rect': ShapeObject,
        'shape_ellipse': ShapeObject,
        'shape_arrow': ShapeObject,
        'text_box': TextBoxObject,
        'image': ImageObject,
        'math': MathObject,
        'math_no_engine': MathObject,
        'math_ink': MathObject,
        'unknown': UnknownObject,
      };
      for (final MapEntry(key: name, value: type) in types.entries) {
        final o = PageObject.fromJson(_json(name));
        expect(o.runtimeType, type, reason: name);
        expect(o, kSampleObjects[name], reason: name);
        expect(EntityJson.decode(EntityKind.pageObject, _json(name)), o);
      }
    });

    test('another type → UnknownObject keeping the raw JSON', () {
      final raw = _with(_json('text_box'), 'type', 'video');
      final o = PageObject.fromJson(raw);
      expect(o, isA<UnknownObject>());
      expect(o.type, 'video');
      expect(o.toJson(), raw);
      expect(o.frame, const ElementFrame(PageRect(60, 620, 360, 690.5)));
    });

    test(
      'a known type with an enum name this app does not know → UnknownObject '
      '(CP-6)',
      () {
        final cases = <String, Map<String, Object?>>{
          'shape: heart': _with(_json('shape_rect'), 'shape', 'heart'),
          'dash: wavy': _withStyle(_json('shape_rect'), 'dash', 'wavy'),
          'arrowHeads: triple': _withStyle(
            _json('shape_arrow'),
            'arrowHeads',
            'triple',
          ),
          'align: justify': _withStyle(_json('text_box'), 'align', 'justify'),
        };
        for (final MapEntry(key: name, value: raw) in cases.entries) {
          final o = PageObject.fromJson(raw);
          expect(o, isA<UnknownObject>(), reason: name);
          expect(o.type, raw['type'], reason: name);
          expect(o.toJson(), raw, reason: name);
          expect(o.id, raw['id']);
          expect(o.version, kV);
        }
        // A direct style read reports the unknown name as a FormatException.
        expect(
          () =>
              ShapeStyle.fromJson(const {'strokeColorArgb': 1, 'dash': 'wavy'}),
          throwsFormatException,
        );
        expect(
          () => TextBoxStyle.fromJson(const {'align': 'justify'}),
          throwsFormatException,
        );
      },
    );

    test(
      'a known type with a missing or wrong required key → FormatException',
      () {
        final bad = <String, Map<String, Object?>>{
          'shape geometry': _without(_json('shape_rect'), 'geometry'),
          'shape style': _without(_json('shape_rect'), 'style'),
          'shape kind type': _with(_json('shape_rect'), 'shape', 3),
          'style color': _withStyle(
            _json('shape_rect'),
            'strokeColorArgb',
            null,
          ),
          'style width type': _withStyle(
            _json('shape_rect'),
            'strokeWidth',
            '2',
          ),
          'geometry both': _with(_json('shape_rect'), 'geometry', {
            'poly': [0, 0, 1, 1],
            'closed': false,
            'ellipse': [0, 0, 1, 1, 0],
          }),
          'geometry neither': _with(_json('shape_rect'), 'geometry', {
            'closed': false,
          }),
          'geometry odd': _with(_json('shape_rect'), 'geometry', {
            'poly': [0, 0, 1],
            'closed': false,
          }),
          'geometry one point': _with(_json('shape_rect'), 'geometry', {
            'poly': [0, 0],
            'closed': false,
          }),
          'geometry closed': _with(_json('shape_rect'), 'geometry', {
            'poly': [0, 0, 1, 1],
          }),
          'geometry ellipse frame': _with(_json('shape_rect'), 'geometry', {
            'ellipse': [0, 0, 1, 1],
          }),
          'text frame': _without(_json('text_box'), 'frame'),
          'text frame bad': _with(_json('text_box'), 'frame', [0, 0, -1, 1, 0]),
          'text text type': _with(_json('text_box'), 'text', 7),
          'image px': _with(_json('image'), 'px', [400]),
          'image px type': _with(_json('image'), 'px', [400.5, 300]),
          'image asset': _with(_json('image'), 'assetId', null),
          'math latex': _without(_json('math'), 'latex'),
          'math engine type': _with(_json('math'), 'engine', 1),
          'createdAt type': _with(_json('math'), 'createdAt', 'x'),
          'version': _with(_json('math'), 'version', 'bad'),
          'type missing': _without(_json('math'), 'type'),
        };
        for (final MapEntry(key: name, value: raw) in bad.entries) {
          expect(
            () => PageObject.fromJson(raw),
            throwsFormatException,
            reason: name,
          );
        }
      },
    );

    test('unknown keys inside a known type are ignored', () {
      for (final name in ['shape_rect', 'text_box', 'image', 'math']) {
        final raw = {
          ..._json(name),
          'futureKey': [1, 2],
          'style2': {'x': 1},
        };
        final o = PageObject.fromJson(raw);
        expect(o, kSampleObjects[name], reason: name);
        expect(o.toJson().containsKey('futureKey'), isFalse);
      }
    });

    test('UnknownObject: id, pageId, type, createdAt, updatedAt required', () {
      for (final key in ['id', 'pageId', 'type', 'createdAt', 'updatedAt']) {
        expect(
          () => UnknownObject(_without(_json('unknown'), key)),
          throwsFormatException,
          reason: key,
        );
        expect(
          () => PageObject.fromJson(_without(_json('unknown'), key)),
          throwsFormatException,
          reason: key,
        );
      }
      expect(
        () => UnknownObject(_with(_json('unknown'), 'deletedAt', 'x')),
        throwsFormatException,
      );
      expect(
        () => UnknownObject({..._json('unknown'), 'when': DateTime(2026)}),
        throwsFormatException,
        reason: 'not a JSON value',
      );
    });

    test("a shape's frame is computed from the geometry; read ignores it", () {
      final raw = _with(_json('shape_rect'), 'frame', [0, 0, 1, 1, 2]);
      final o = PageObject.fromJson(raw) as ShapeObject;
      expect(o.frame, const ElementFrame(PageRect(120, 80, 320, 200)));
      expect(o, kSampleObjects['shape_rect']);
      final noFrame = PageObject.fromJson(
        _without(_json('shape_rect'), 'frame'),
      );
      expect(noFrame, kSampleObjects['shape_rect']);
      expect(_json('shape_ellipse')['frame'], [
        100.0,
        300.0,
        260.0,
        400.0,
        0.5,
      ]);
    });

    test(
      'UnknownObject.frame: from rawJson when decodable, else (0,0,1,1)',
      () {
        const placeholder = ElementFrame(PageRect(0, 0, 1, 1));
        expect(
          kSampleObjects['unknown']!.frame,
          const ElementFrame(PageRect(400, 100, 450, 150)),
        );
        for (final frame in <Object?>[
          null,
          'x',
          [1, 2, 3],
          [10, 0, 5, 1, 0],
          {'l': 0},
        ]) {
          final raw = frame == null
              ? _without(_json('unknown'), 'frame')
              : _with(_json('unknown'), 'frame', frame);
          final o = UnknownObject(raw);
          expect(o.frame, placeholder, reason: '$frame');
          expect(o.bounds, placeholder.rect);
          expect(o.toJson(), {...raw, 'deletedAt': null});
        }
      },
    );

    test('the local limits are not applied on read (6.4.1 commands only)', () {
      final longText = 'a' * (PageObjectLimits.maxTextLength + 1);
      final text = PageObject.fromJson(
        _with(_json('text_box'), 'text', longText),
      ) as TextBoxObject;
      expect(text.text.length, PageObjectLimits.maxTextLength + 1);
      final latex = 'x' * (PageObjectLimits.maxLatexLength + 1);
      expect(
        (PageObject.fromJson(
          _with(_json('math'), 'latex', latex),
        ) as MathObject).latex,
        latex,
      );
      final many = [
        for (var i = 0; i <= PageObjectLimits.maxPolylinePoints; i++) ...[
          i.toDouble(),
          (i * 2).toDouble(),
        ],
      ];
      final shape = PageObject.fromJson(
        _with(_json('shape_rect'), 'geometry', {'poly': many, 'closed': false}),
      ) as ShapeObject;
      expect(
        (shape.geometry as PolylineGeometry).points,
        hasLength(PageObjectLimits.maxPolylinePoints + 1),
      );
    });
  });

  group('6.3 always-written keys, no normalization on read', () {
    test('the key sets are fixed per type (SYNC kPageObjectTypeKeys)', () {
      const common = {
        'id',
        'pageId',
        'type',
        'frame',
        'createdAt',
        'updatedAt',
        'deletedAt',
        'version',
      };
      const perType = {
        'shape_rect': {'shape', 'geometry', 'style'},
        'text_box': {'text', 'style'},
        'image': {'assetId', 'px'},
        'math': {'latex', 'style', 'engine', 'ink'},
        'math_no_engine': {'latex', 'style', 'engine', 'ink'},
        'math_ink': {'latex', 'style', 'engine', 'ink'},
      };
      for (final MapEntry(key: name, value: keys) in perType.entries) {
        expect(_json(name).keys.toSet(), {...common, ...keys}, reason: name);
      }
      expect(_json('math_no_engine')['engine'], isNull);
      expect(_json('math_no_engine').containsKey('engine'), isTrue);
      // (math pen) ink: always written, null when the formula has none.
      expect(_json('math').containsKey('ink'), isTrue);
      expect(_json('math')['ink'], isNull);
      expect(_json('math_ink')['ink'], hasLength(2));
      final shapeStyle = _json('shape_rect')['style']! as Map<String, Object?>;
      expect(shapeStyle.keys.toSet(), {
        'strokeColorArgb',
        'strokeWidth',
        'strokeOpacity',
        'dash',
        'fillColorArgb',
        'fillOpacity',
        'arrowHeads',
      });
      expect(shapeStyle['fillColorArgb'], isNull);
      final textStyle =
          TextBoxObject(
                id: 't',
                pageId: 'p',
                frame: const ElementFrame(PageRect(0, 0, 1, 1)),
                text: '',
                style: const TextBoxStyle(),
                createdAt: 0,
              ).toJson()['style']!
              as Map<String, Object?>;
      expect(textStyle.keys.toSet(), {
        'fontSizePt',
        'colorArgb',
        'bold',
        'align',
        'lineHeight',
        'backgroundArgb',
      });
      expect(textStyle['backgroundArgb'], isNull);
      expect((_json('math')['style']! as Map<String, Object?>).keys.toSet(), {
        'colorArgb',
        'fontSizePt',
      });
      expect(_json('shape_ellipse')['geometry'], {
        'ellipse': [100.0, 300.0, 260.0, 400.0, 0.5],
      });
    });

    test('absent optional keys read as the defaults / null', () {
      final math = PageObject.fromJson(_without(_json('math'), 'engine'));
      expect((math as MathObject).engineId, isNull);
      final shape = PageObject.fromJson(
        _with(_json('shape_rect'), 'style', {'strokeColorArgb': 7}),
      ) as ShapeObject;
      expect(shape.style, const ShapeStyle(strokeColorArgb: 7));
      final text = PageObject.fromJson(
        _with(_json('text_box'), 'style', const {}),
      ) as TextBoxObject;
      expect(text.style, const TextBoxStyle());
      final noMeta = PageObject.fromJson(
        _without(_without(_json('image'), 'deletedAt'), 'version'),
      );
      expect(noMeta.deletedAt, isNull);
      expect(noMeta.version, isNull);
    });

    test('remote values round-trip unchanged (no clamping, no alpha fix)', () {
      final raw = _with(_json('shape_rect'), 'style', {
        'strokeColorArgb': 0x00123456,
        'strokeWidth': 100.0,
        'strokeOpacity': 0.0,
        'dash': 'solid',
        'fillColorArgb': 0x11FFFFFF,
        'fillOpacity': 5.0,
        'arrowHeads': 'end',
      });
      expect(PageObject.fromJson(raw).toJson(), raw);
      final text = _with(_json('text_box'), 'style', {
        'fontSizePt': 500.0,
        'colorArgb': 0x10000000,
        'bold': false,
        'align': 'end',
        'lineHeight': 9.0,
        'backgroundArgb': 0x01020304,
      });
      expect(PageObject.fromJson(text).toJson(), text);
      final rotated = _with(_json('image'), 'frame', [
        0.0,
        0.0,
        10.0,
        10.0,
        7.0,
      ]);
      expect(PageObject.fromJson(rotated).frame.rotation, 7.0);
      expect(PageObject.fromJson(rotated).toJson(), rotated);
    });
  });

  group('UnknownObject (C-12)', () {
    test('round-trips key for key, through jsonEncode too', () {
      final raw = _json('unknown');
      final o = UnknownObject(raw);
      expect(o.toJson(), raw);
      final again = PageObject.fromJson(
        jsonDecode(jsonEncode(o.toJson())) as Map<String, Object?>,
      );
      expect(again, o);
      expect(again.hashCode, o.hashCode);
      expect(again.type, 'sticker');
      expect((again.toJson()['layers']! as List)[1], {
        'k': 'b',
        'v': [true, null, 2.5],
      });
    });

    test('rawJson is an unmodifiable deep copy', () {
      final nested = <String, Object?>{
        'pack': 'animals',
        'tint': [1, 2],
      };
      final input = <String, Object?>{..._json('unknown'), 'sticker': nested};
      final o = UnknownObject(input);
      nested['pack'] = 'changed';
      (nested['tint']! as List).add(3);
      input['futureKey'] = 'changed';
      expect(o.rawJson['sticker'], {
        'pack': 'animals',
        'tint': [1, 2],
      });
      expect(o.rawJson['futureKey'], '미래');
      expect(() => o.rawJson['x'] = 1, throwsUnsupportedError);
      expect(
        () => (o.rawJson['sticker']! as Map<String, Object?>)['x'] = 1,
        throwsUnsupportedError,
      );
      expect(
        () => ((o.rawJson['sticker']! as Map)['tint'] as List).add(9),
        throwsUnsupportedError,
      );
    });

    test('meta values are read from rawJson', () {
      final raw = {
        ..._json('unknown'),
        'deletedAt': kT + 50,
        'updatedAt': kT + 50,
      };
      final o = UnknownObject(raw);
      expect(o.id, '0193f1d2-7c4b-7000-8000-0000000000b8');
      expect(o.pageId, kSamplePageId);
      expect(o.createdAt, kT + 7);
      expect(o.updatedAt, kT + 50);
      expect(o.deletedAt, kT + 50);
      expect(o.isDeleted, isTrue);
      expect(o.version, kV);
      expect(o.kind, EntityKind.pageObject);
    });

    test('== is the deep equality of toJson()', () {
      final a = UnknownObject(_json('unknown'));
      final b = UnknownObject(
        jsonDecode(jsonEncode(_json('unknown'))) as Map<String, Object?>,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(UnknownObject(_with(_json('unknown'), 'futureKey', 'x'))),
      );
    });
  });

  group('referencedAssets', () {
    test('image: its asset; shape, text, math: none', () {
      expect(kSampleObjects['image']!.referencedAssets, {kSampleImageAssetId});
      for (final name in ['shape_rect', 'text_box', 'math']) {
        expect(kSampleObjects[name]!.referencedAssets, isEmpty, reason: name);
      }
    });

    test('UnknownObject: a top-level AssetId (64 lowercase hex) only', () {
      final withAsset = UnknownObject(
        _with(_json('unknown'), 'assetId', kSampleImageAssetId),
      );
      expect(withAsset.referencedAssets, {kSampleImageAssetId});
      for (final value in <Object?>[
        null,
        42,
        'abc',
        kSampleImageAssetId.toUpperCase(),
        '${kSampleImageAssetId}0',
      ]) {
        final o = UnknownObject(_with(_json('unknown'), 'assetId', value));
        expect(o.referencedAssets, isEmpty, reason: '$value');
      }
      // Nested asset ids are not reported.
      final nested = UnknownObject(
        _with(_json('unknown'), 'sticker', {'assetId': kSampleImageAssetId}),
      );
      expect(nested.referencedAssets, isEmpty);
    });

    test('an image read as UnknownObject (unknown type) keeps its asset', () {
      final raw = _with(_json('image'), 'type', 'image2');
      final o = PageObject.fromJson(raw);
      expect(o, isA<UnknownObject>());
      expect(o.referencedAssets, {kSampleImageAssetId});
    });
  });
}
