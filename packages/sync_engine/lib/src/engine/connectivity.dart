import 'dart:async';

abstract interface class ConnectivitySignal {
  bool get isOnline;

  /// Distinct values.
  Stream<bool> get changes;
}

final class AlwaysOnlineSignal implements ConnectivitySignal {
  const AlwaysOnlineSignal();

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

/// Test/manual control.
final class ManualConnectivitySignal implements ConnectivitySignal {
  ManualConnectivitySignal({bool online = true}) : _current = online;

  bool _current;
  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );

  @override
  bool get isOnline => _current;

  @override
  Stream<bool> get changes => _changes.stream;

  void set(bool online) {
    if (online == _current) return;
    _current = online;
    _changes.add(online);
  }
}
