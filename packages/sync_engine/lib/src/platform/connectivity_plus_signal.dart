import 'package:connectivity_plus/connectivity_plus.dart';

import '../engine/connectivity.dart';

final class ConnectivityPlusSignal implements ConnectivitySignal {
  ConnectivityPlusSignal({Connectivity? connectivity});

  @override
  bool get isOnline => throw UnimplementedError('SYNC T17');

  @override
  Stream<bool> get changes => throw UnimplementedError('SYNC T17');

  Future<void> dispose() => throw UnimplementedError('SYNC T17');
}
