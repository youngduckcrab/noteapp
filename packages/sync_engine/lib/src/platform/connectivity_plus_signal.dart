// The connectivity_plus adapter of ConnectivitySignal (6.8.2): online = any result other
// than none. Starts online (the engine's own connection failures go offline anyway) until
// the first check answers; changes are distinct.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../engine/connectivity.dart';

final class ConnectivityPlusSignal implements ConnectivitySignal {
  ConnectivityPlusSignal({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      _onResults,
      // A failing platform stream leaves the last known value.
      onError: (Object _) {},
    );
    unawaited(
      _connectivity.checkConnectivity().then(
        _onResults,
        onError: (Object _) {},
      ),
    );
  }

  final Connectivity _connectivity;
  late final StreamSubscription<List<ConnectivityResult>> _subscription;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  bool _online = true;
  bool _disposed = false;

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void _onResults(List<ConnectivityResult> results) {
    if (_disposed) return;
    final online = _isOnline(results);
    if (online == _online) return;
    _online = online;
    _changes.add(online);
  }

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get changes => _changes.stream;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final closed = _changes.close();
    await _subscription.cancel();
    await closed;
  }
}
