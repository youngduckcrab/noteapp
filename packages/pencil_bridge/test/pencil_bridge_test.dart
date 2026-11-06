// PencilBridge over fake channels (docs/plans/m5-7/01-infra.md 4.4.2, 4.4.3,
// 6.12.1 and 6.12.4; contract 00-overview 7.2.13 and 7.4.6 v2.1 — a service
// package adapter may fake its own channels).
//
// iOS is selected with debugDefaultTargetPlatformOverride; the native side is
// a mock stream handler that counts 'listen' / 'cancel' and a mock method
// handler for 'capabilities'.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pencil_bridge/pencil_bridge.dart';
import 'package:pencil_bridge/src/wire.dart';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

const EventChannel _events = EventChannel(PencilWire.eventChannel);
const MethodChannel _methods = MethodChannel(PencilWire.methodChannel);

/// The fake native event side: counts listen / cancel and keeps the sink of
/// the current native subscription.
final class _FakeNative {
  _FakeNative() {
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          listens++;
          this.sink = sink;
        },
        onCancel: (arguments) {
          cancels++;
          sink = null;
        },
      ),
    );
  }

  int listens = 0;
  int cancels = 0;
  MockStreamHandlerEventSink? sink;

  void send(Object? event) => sink!.success(event);
}

/// Lets the channel round trips (listen, cancel, events) finish.
Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, Object?> _tap({Object? t = 1.5, Object? action = 'switchEraser'}) =>
    {'type': 'tap', 't': t, 'action': action};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    PencilBridge.debugReset();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    PencilBridge.debugReset();
    _messenger
      ..setMockStreamHandler(_events, null)
      ..setMockMethodCallHandler(_methods, null);
  });

  group('PencilWire.decode (4.4.3)', () {
    test('the four event types', () {
      expect(
        PencilWire.decode({
          'type': 'tap',
          't': 12.5,
          'action': 'switchEraser',
          'x': 10.0,
          'y': 20.0,
          'z': 0.25,
        }),
        const PencilTap(
          Duration(microseconds: 12500000),
          preferredAction: 'switchEraser',
          position: Offset(10, 20),
          z: 0.25,
        ),
      );
      expect(
        PencilWire.decode({
          'type': 'squeeze',
          't': 0.000001,
          'phase': 'began',
          'action': 'showContextualPalette',
          'x': 1.0,
          'y': 2.0,
          'z': 0.5,
          'roll': 0.75,
        }),
        const PencilSqueeze(
          Duration(microseconds: 1),
          phase: 'began',
          preferredAction: 'showContextualPalette',
          position: Offset(1, 2),
          z: 0.5,
          roll: 0.75,
        ),
      );
      expect(
        PencilWire.decode({
          'type': 'hover',
          't': 3.0,
          'x': 100.5,
          'y': 200.25,
          'z': 0.1,
          'altitude': 1.2,
          'azimuth': -0.5,
          'roll': 0.3,
        }),
        const PencilHover(
          Duration(seconds: 3),
          position: Offset(100.5, 200.25),
          z: 0.1,
          altitude: 1.2,
          azimuth: -0.5,
          roll: 0.3,
        ),
      );
      expect(
        PencilWire.decode({'type': 'roll', 't': 4.25, 'angle': 1.5}),
        const PencilRoll(Duration(microseconds: 4250000), angle: 1.5),
      );
    });

    test('optional keys may be missing or null', () {
      expect(
        PencilWire.decode(_tap()),
        const PencilTap(
          Duration(microseconds: 1500000),
          preferredAction: 'switchEraser',
        ),
      );
      expect(
        PencilWire.decode({
          'type': 'hover',
          't': 1,
          'x': 1,
          'y': 2,
          'z': null,
          'altitude': null,
        }),
        const PencilHover(Duration(seconds: 1), position: Offset(1, 2)),
      );
      expect(
        PencilWire.decode({
          'type': 'squeeze',
          't': 1,
          'phase': 'ended',
          'action': 'ignore',
        }),
        const PencilSqueeze(
          Duration(seconds: 1),
          phase: 'ended',
          preferredAction: 'ignore',
        ),
      );
    });

    test('a tap / squeeze position needs both x and y', () {
      final onlyX = PencilWire.decode({..._tap(), 'x': 5.0})! as PencilTap;
      expect(onlyX.position, isNull);
      final onlyY =
          PencilWire.decode({..._tap(), 'y': 5.0, 'z': 0.5})! as PencilTap;
      expect(onlyY.position, isNull);
      expect(onlyY.z, 0.5);
      final squeeze =
          PencilWire.decode({
                'type': 'squeeze',
                't': 1,
                'phase': 'changed',
                'action': 'ignore',
                'y': 3,
              })!
              as PencilSqueeze;
      expect(squeeze.position, isNull);
    });

    test('ints are taken as numbers', () {
      expect(
        PencilWire.decode({'type': 'hover', 't': 2, 'x': 10, 'y': 20, 'z': 1}),
        const PencilHover(Duration(seconds: 2), position: Offset(10, 20), z: 1),
      );
      expect(
        PencilWire.decode({'type': 'roll', 't': 0, 'angle': -1}),
        const PencilRoll(Duration.zero, angle: -1),
      );
    });

    test('t is seconds → Duration microseconds, rounded', () {
      expect(
        PencilWire.decode(_tap(t: 1.0000004))!.timestamp,
        const Duration(seconds: 1),
      );
      expect(
        PencilWire.decode(_tap(t: 86400.123456))!.timestamp,
        const Duration(days: 1, microseconds: 123456),
      );
    });

    test('unknown action / phase strings are kept as sent', () {
      expect(
        (PencilWire.decode(_tap(action: 'newAction2030'))! as PencilTap)
            .preferredAction,
        'newAction2030',
      );
      expect(
        (PencilWire.decode({
                  'type': 'squeeze',
                  't': 1,
                  'phase': 'wobble',
                  'action': 'x',
                })!
                as PencilSqueeze)
            .phase,
        'wobble',
      );
    });

    test('drops: not a map, unknown type, missing required key, wrong value '
        'type', () {
      for (final bad in <Object?>[
        null,
        'tap',
        42,
        [1, 2],
        <String, Object?>{},
        {'type': 'pinch', 't': 1},
        {'type': 'TAP', 't': 1, 'action': 'ignore'},
        {'type': 1, 't': 1},
        {'t': 1, 'action': 'ignore'},
        {'type': 'tap', 'action': 'ignore'}, // no t
        _tap(t: '1.5'),
        _tap(t: double.nan),
        _tap(t: double.infinity),
        {'type': 'tap', 't': 1}, // no action
        _tap(action: 3),
        {..._tap(), 'x': '10', 'y': 1.0},
        {..._tap(), 'z': true},
        {'type': 'squeeze', 't': 1, 'action': 'ignore'}, // no phase
        {'type': 'squeeze', 't': 1, 'phase': 'began'}, // no action
        {'type': 'squeeze', 't': 1, 'phase': 1, 'action': 'ignore'},
        {'type': 'hover', 't': 1, 'x': 1}, // no y
        {'type': 'hover', 't': 1, 'y': 1}, // no x
        {'type': 'hover', 't': 1, 'x': 1, 'y': 2, 'roll': 'a'},
        {'type': 'roll', 't': 1}, // no angle
        {'type': 'roll', 't': 1, 'angle': '1'},
      ]) {
        expect(PencilWire.decode(bad), isNull, reason: '$bad');
      }
    });

    test('wire constants (4.4.2)', () {
      expect(PencilWire.eventChannel, 'dev.noteapp/pencil/events');
      expect(PencilWire.methodChannel, 'dev.noteapp/pencil/methods');
      expect(PencilWire.capabilitiesMethod, 'capabilities');
      expect(PencilWire.types, {'tap', 'squeeze', 'hover', 'roll'});
      expect(PencilWire.actions, {
        'ignore',
        'switchEraser',
        'switchPrevious',
        'showColorPalette',
        'showInkAttributes',
        'showContextualPalette',
        'runSystemShortcut',
        'unknown',
      });
      expect(PencilWire.phases, {'began', 'changed', 'ended', 'cancelled'});
      expect(PencilWire.eventKeys.keys.toSet(), PencilWire.types);
    });
  });

  group('PencilBridge.events on iOS (6.12.1)', () {
    test('isSupported follows the target platform', () {
      expect(PencilBridge.isSupported, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PencilBridge.isSupported, isFalse);
    });

    test('the stream is cached (identical) and broadcast', () {
      _FakeNative();
      final first = PencilBridge.events;
      expect(identical(PencilBridge.events, first), isTrue);
      expect(first.isBroadcast, isTrue);
      PencilBridge.debugReset();
      expect(identical(PencilBridge.events, first), isFalse);
    });

    test('decodes the native events; undecodable ones are dropped and '
        'counted, never an error event', () async {
      final native = _FakeNative();
      final received = <PencilEvent>[];
      final errors = <Object>[];
      final sub = PencilBridge.events.listen(received.add, onError: errors.add);
      await _flush();
      expect(native.listens, 1);

      native
        ..send(_tap())
        ..send({'type': 'pinch', 't': 1})
        ..send({'type': 'roll', 't': 2, 'angle': 1})
        ..send('garbage')
        ..send({'type': 'hover', 't': 3, 'x': 1, 'y': 2});
      await _flush();

      expect(received, const [
        PencilTap(
          Duration(microseconds: 1500000),
          preferredAction: 'switchEraser',
        ),
        PencilRoll(Duration(seconds: 2), angle: 1),
        PencilHover(Duration(seconds: 3), position: Offset(1, 2)),
      ]);
      expect(PencilBridge.debugDroppedEvents, 2);
      expect(errors, isEmpty);
      await sub.cancel();
    });

    test('two listeners → one cancel keeps the native side → last cancel '
        'detaches once → a new listener attaches again (review M-8)', () async {
      final native = _FakeNative();
      final a = <PencilEvent>[];
      final b = <PencilEvent>[];

      final subA = PencilBridge.events.listen(a.add);
      final subB = PencilBridge.events.listen(b.add);
      await _flush();
      expect(native.listens, 1);
      expect(native.cancels, 0);

      native.send(_tap());
      await _flush();
      expect(a, hasLength(1));
      expect(b, hasLength(1));

      await subA.cancel();
      await _flush();
      expect(native.cancels, 0, reason: 'one listener is left');
      native.send({'type': 'roll', 't': 2, 'angle': 0.5});
      await _flush();
      expect(a, hasLength(1));
      expect(b, hasLength(2));

      await subB.cancel();
      await _flush();
      expect(native.cancels, 1, reason: 'last cancel detaches');
      expect(native.listens, 1);
      expect(native.sink, isNull);

      final c = <PencilEvent>[];
      final subC = PencilBridge.events.listen(c.add);
      await _flush();
      expect(native.listens, 2, reason: 'a later listener attaches again');
      native.send({'type': 'roll', 't': 3, 'angle': 0.25});
      await _flush();
      expect(c, const [PencilRoll(Duration(seconds: 3), angle: 0.25)]);

      await subC.cancel();
      await _flush();
      expect(native.cancels, 2);
    });

    test(
      'a native error is dropped (printed once); the stream goes on',
      () async {
        final native = _FakeNative();
        final printed = <String?>[];
        final oldPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) => printed.add(message);
        addTearDown(() => debugPrint = oldPrint);

        final received = <PencilEvent>[];
        final errors = <Object>[];
        var done = false;
        final sub = PencilBridge.events.listen(
          received.add,
          onError: errors.add,
          onDone: () => done = true,
        );
        await _flush();
        native.sink!.error(code: 'boom', message: 'native failure');
        native.sink!.error(code: 'boom2');
        native.send(_tap());
        await _flush();

        expect(errors, isEmpty);
        expect(done, isFalse);
        expect(received, hasLength(1));
        expect(printed, hasLength(1));
        expect(printed.single, contains('boom'));
        await sub.cancel();
      },
    );
  });

  group('PencilBridge.capabilities on iOS', () {
    test('decodes the method result', () async {
      final calls = <MethodCall>[];
      _messenger.setMockMethodCallHandler(_methods, (call) async {
        calls.add(call);
        return <String, Object?>{
          'os': '17.5.1',
          'squeeze': true,
          'hover': true,
          'roll': true,
          'prefersPencilOnlyDrawing': true,
          'preferredTapAction': 'switchPrevious',
          'preferredSqueezeAction': 'showContextualPalette',
        };
      });
      expect(
        await PencilBridge.capabilities(),
        const PencilCapabilities(
          os: '17.5.1',
          squeeze: true,
          hover: true,
          roll: true,
          prefersPencilOnlyDrawing: true,
          preferredTapAction: 'switchPrevious',
          preferredSqueezeAction: 'showContextualPalette',
        ),
      );
      expect(calls.single.method, 'capabilities');
    });

    test('missing keys (and wrong types) keep the defaults', () async {
      _messenger.setMockMethodCallHandler(
        _methods,
        (call) async => <String, Object?>{
          'os': '16.4',
          'hover': true,
          'squeeze': 'yes',
          'preferredTapAction': 7,
        },
      );
      expect(
        await PencilBridge.capabilities(),
        const PencilCapabilities(os: '16.4', hover: true),
      );
      expect(
        PencilCapabilities.fromWire(const {}),
        PencilCapabilities.unsupported,
      );
    });

    test('PlatformException and MissingPluginException are rethrown', () async {
      _messenger.setMockMethodCallHandler(
        _methods,
        (call) async => throw PlatformException(code: 'no-view'),
      );
      await expectLater(
        PencilBridge.capabilities(),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'no-view'),
        ),
      );

      _messenger.setMockMethodCallHandler(_methods, null);
      await expectLater(
        PencilBridge.capabilities(),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test(
      'a result that is not a map → PlatformException(invalid-result)',
      () async {
        _messenger.setMockMethodCallHandler(_methods, (call) async => 'ok');
        await expectLater(
          PencilBridge.capabilities(),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'invalid-result',
            ),
          ),
        );
      },
    );
  });

  group('other platforms: no channel call at all', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      test(platform.name, () async {
        debugDefaultTargetPlatformOverride = platform;
        final native = _FakeNative();
        var methodCalls = 0;
        _messenger.setMockMethodCallHandler(_methods, (call) async {
          methodCalls++;
          return null;
        });

        expect(PencilBridge.isSupported, isFalse);
        expect(
          await PencilBridge.capabilities(),
          PencilCapabilities.unsupported,
        );
        final done = Completer<void>();
        final received = <PencilEvent>[];
        PencilBridge.events.listen(received.add, onDone: done.complete);
        await done.future;
        await _flush();

        expect(received, isEmpty);
        expect(native.listens, 0);
        expect(methodCalls, 0);
        expect(PencilBridge.events.isBroadcast, isTrue);
      });
    }
  });

  group('value types', () {
    test('== / hashCode / toString', () {
      const tap = PencilTap(
        Duration(seconds: 1),
        preferredAction: 'ignore',
        position: Offset(1, 2),
        z: 0.5,
      );
      expect(
        tap,
        const PencilTap(
          Duration(seconds: 1),
          preferredAction: 'ignore',
          position: Offset(1, 2),
          z: 0.5,
        ),
      );
      expect(
        tap.hashCode,
        const PencilTap(
          Duration(seconds: 1),
          preferredAction: 'ignore',
          position: Offset(1, 2),
          z: 0.5,
        ).hashCode,
      );
      expect(
        tap,
        isNot(
          const PencilTap(
            Duration(seconds: 2),
            preferredAction: 'ignore',
            position: Offset(1, 2),
            z: 0.5,
          ),
        ),
      );
      expect(tap.toString(), contains('ignore'));

      const squeeze = PencilSqueeze(
        Duration(seconds: 1),
        phase: 'began',
        preferredAction: 'ignore',
        roll: 1,
      );
      expect(
        squeeze,
        const PencilSqueeze(
          Duration(seconds: 1),
          phase: 'began',
          preferredAction: 'ignore',
          roll: 1,
        ),
      );
      expect(
        squeeze,
        isNot(
          const PencilSqueeze(
            Duration(seconds: 1),
            phase: 'ended',
            preferredAction: 'ignore',
            roll: 1,
          ),
        ),
      );
      expect(squeeze.toString(), contains('began'));

      const hover = PencilHover(
        Duration(seconds: 1),
        position: Offset(1, 2),
        azimuth: 0.5,
      );
      expect(
        hover,
        const PencilHover(
          Duration(seconds: 1),
          position: Offset(1, 2),
          azimuth: 0.5,
        ),
      );
      expect(
        hover,
        isNot(const PencilHover(Duration(seconds: 1), position: Offset(1, 2))),
      );
      expect(hover.toString(), contains('azimuth: 0.5'));

      const roll = PencilRoll(Duration(seconds: 1), angle: 1);
      expect(roll, const PencilRoll(Duration(seconds: 1), angle: 1));
      expect(roll, isNot(const PencilRoll(Duration(seconds: 1), angle: 2)));
      expect(
        roll.hashCode,
        const PencilRoll(Duration(seconds: 1), angle: 1).hashCode,
      );
      expect(roll.toString(), contains('angle: 1'));

      // Different event types never compare equal.
      expect(
        const PencilRoll(Duration.zero, angle: 0),
        isNot(const PencilHover(Duration.zero, position: Offset.zero)),
      );

      const caps = PencilCapabilities(os: '18.0', hover: true);
      expect(caps, const PencilCapabilities(os: '18.0', hover: true));
      expect(
        caps.hashCode,
        const PencilCapabilities(os: '18.0', hover: true).hashCode,
      );
      expect(caps, isNot(const PencilCapabilities(os: '18.0')));
      expect(caps.toString(), contains('hover: true'));
    });

    test('PencilCapabilities defaults and unsupported', () {
      const c = PencilCapabilities(os: '17.0');
      expect(c.squeeze, isFalse);
      expect(c.hover, isFalse);
      expect(c.roll, isFalse);
      expect(c.prefersPencilOnlyDrawing, isFalse);
      expect(c.preferredTapAction, 'unknown');
      expect(c.preferredSqueezeAction, 'unknown');
      expect(PencilCapabilities.unsupported.os, '');
      // unsupported equals a plain value with os '' (value equality).
      final plain = PencilCapabilities.fromWire(const {'os': ''});
      expect(PencilCapabilities.unsupported, plain);
      expect(identical(PencilCapabilities.unsupported, plain), isFalse);
    });
  });
}
