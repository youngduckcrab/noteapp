import '../backend/remote_chunk.dart';
import '../common/errors.dart';

enum FakeOp {
  any,
  commit,
  fetch,
  watch,
  count,
  delete,
  profile,
  device,
  byId,
  stat,
  upload,
  download,
}

sealed class FakeFault {
  const FakeFault();
}

/// Fails before the server applies anything.
final class FakeNetworkError extends FakeFault {
  const FakeNetworkError();
}

/// The server applies the commit, but the client receives a network error.
final class FakeAckLost extends FakeFault {
  const FakeAckLost();
}

final class FakeErrorCode extends FakeFault {
  const FakeErrorCode(this.code);
  final SyncErrorCode code;
}

/// Upload/download stops after [fraction] of bytes with a network error.
final class FakeInterrupt extends FakeFault {
  const FakeInterrupt(this.fraction);
  final double fraction;
}

final class FakeNetworkLink {
  FakeNetworkLink({
    this.latency = const Duration(milliseconds: 50),
    bool online = true,
  });

  /// One way.
  Duration latency;

  bool get online => throw UnimplementedError('SYNC T5');

  /// Offline → open watch streams end with network error.
  void setOnline(bool online) => throw UnimplementedError('SYNC T5');

  void failNext(FakeFault fault, {FakeOp op = FakeOp.any, int times = 1}) =>
      throw UnimplementedError('SYNC T5');

  /// Fails commits whose payload matches (for rejectedByServer tests).
  void rejectCommitsWhere(
    bool Function(ChunkWrite chunk) test,
    SyncErrorCode code,
  ) => throw UnimplementedError('SYNC T5');

  int callCount(FakeOp op) => throw UnimplementedError('SYNC T5');
}
