// T17: ConnectivityPlusSignal (6.8.2) on a fake Connectivity: online until the first check
// answers, online = any result other than none, distinct changes, platform errors keep the
// last value, dispose closes the changes.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/platform.dart';
import 'package:sync_engine/sync_engine.dart';

final class _Connectivity implements Connectivity {
  _Connectivity(this.initial);

  final Completer<List<ConnectivityResult>> initial;
  // ignore: close_sinks — lives as long as the test's signal.
  final StreamController<List<ConnectivityResult>> platform =
      StreamController.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => platform.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() => initial.future;
}

void main() {
  test('online until the first check; then the check and every distinct '
      'change', () async {
    final initial = Completer<List<ConnectivityResult>>();
    final fake = _Connectivity(initial);
    final ConnectivitySignal signal = ConnectivityPlusSignal(
      connectivity: fake,
    );
    final seen = <bool>[];
    final sub = signal.changes.listen(seen.add);
    expect(signal.isOnline, isTrue);

    initial.complete([ConnectivityResult.none]);
    await pumpEventQueue();
    expect(signal.isOnline, isFalse);
    expect(seen, [false]);

    fake.platform.add([ConnectivityResult.none]);
    fake.platform.add([ConnectivityResult.wifi]);
    fake.platform.add([ConnectivityResult.wifi, ConnectivityResult.vpn]);
    fake.platform.add([ConnectivityResult.mobile]);
    await pumpEventQueue();
    expect(signal.isOnline, isTrue);
    expect(seen, [false, true]);

    fake.platform.add([]);
    await pumpEventQueue();
    expect(signal.isOnline, isFalse);
    fake.platform.add([ConnectivityResult.ethernet]);
    await pumpEventQueue();
    expect(seen, [false, true, false, true]);
    await sub.cancel();
    await (signal as ConnectivityPlusSignal).dispose();
  });

  test('platform errors keep the last value; dispose closes the changes and '
      'ignores later results', () async {
    final initial = Completer<List<ConnectivityResult>>();
    final fake = _Connectivity(initial);
    final signal = ConnectivityPlusSignal(connectivity: fake);
    initial.completeError(StateError('no plugin'));
    fake.platform.addError(StateError('stream failed'));
    await pumpEventQueue();
    expect(signal.isOnline, isTrue);

    var done = false;
    signal.changes.listen((_) {}, onDone: () => done = true);
    await signal.dispose();
    expect(done, isTrue);
    fake.platform.add([ConnectivityResult.none]);
    await pumpEventQueue();
    expect(signal.isOnline, isTrue);
    expect(fake.platform.hasListener, isFalse);
    await signal.dispose();
  });
}
