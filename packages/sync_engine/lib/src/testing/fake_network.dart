import 'package:meta/meta.dart';

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

/// The network between one simulated device and the FakeSyncServer.
///
/// Every call of a FakeSyncBackend (and of its `blobs`) made through this link
/// is counted per FakeOp (fetchChunks and fetchScope count as FakeOp.fetch,
/// getChunks as FakeOp.byId), waits [latency] for the request and again for
/// the response, and fails with SyncBackendException(network) when the link is
/// offline at the start, when the request arrives or when the response
/// arrives (in the last case the server has already applied the call). Watch
/// batches also arrive [latency] after the server sends them.
///
/// Queued faults ([failNext]) are taken in the order they were queued, by the
/// first call whose op matches (FakeOp.any matches every call). A FakeInterrupt
/// taken by a call other than an upload or download acts like
/// FakeNetworkError. A FakeAckLost taken by a read acts the same way after the
/// server has served it (its reads are counted). A FakeErrorCode is the
/// server's answer: it arrives after the round trip, nothing applied.
final class FakeNetworkLink {
  FakeNetworkLink({
    this.latency = const Duration(milliseconds: 50),
    this._online = true,
  });

  /// One way.
  Duration latency;

  bool _online;
  final List<_QueuedFault> _faults = [];
  final List<_Rejection> _rejections = [];
  final Map<FakeOp, int> _calls = {};
  int _totalCalls = 0;
  final Set<_OfflineListener> _offlineListeners = {};

  bool get online => _online;

  /// Offline → open watch streams end with network error.
  void setOnline(bool online) {
    if (_online == online) return;
    _online = online;
    if (!online) {
      for (final listener in List.of(_offlineListeners)) {
        if (_offlineListeners.contains(listener)) listener.callback();
      }
    }
  }

  void failNext(FakeFault fault, {FakeOp op = FakeOp.any, int times = 1}) {
    if (times < 1) {
      throw ArgumentError.value(times, 'times', 'must be at least 1');
    }
    _faults.add(_QueuedFault(fault, op, times));
  }

  /// Fails commits whose payload matches (for rejectedByServer tests).
  void rejectCommitsWhere(
    bool Function(ChunkWrite chunk) test,
    SyncErrorCode code,
  ) => _rejections.add(_Rejection(test, code));

  int callCount(FakeOp op) =>
      op == FakeOp.any ? _totalCalls : (_calls[op] ?? 0);

  /// Counts one call of [op] and takes the first queued fault that matches it.
  @internal
  FakeFault? beginCall(FakeOp op) {
    if (op == FakeOp.any) {
      throw ArgumentError.value(op, 'op', 'a call has a concrete op');
    }
    _totalCalls++;
    _calls[op] = (_calls[op] ?? 0) + 1;
    for (var i = 0; i < _faults.length; i++) {
      final queued = _faults[i];
      if (queued.op != FakeOp.any && queued.op != op) continue;
      queued.remaining--;
      if (queued.remaining == 0) _faults.removeAt(i);
      return queued.fault;
    }
    return null;
  }

  /// The error code of the first rejection rule that matches one of [chunks].
  @internal
  SyncErrorCode? rejectionFor(List<ChunkWrite> chunks) {
    for (final rejection in _rejections) {
      if (chunks.any(rejection.test)) return rejection.code;
    }
    return null;
  }

  /// Calls [callback] when the link goes offline, until the returned function
  /// is called.
  @internal
  void Function() onOffline(void Function() callback) {
    final listener = _OfflineListener(callback);
    _offlineListeners.add(listener);
    return () => _offlineListeners.remove(listener);
  }
}

final class _QueuedFault {
  _QueuedFault(this.fault, this.op, this.remaining);
  final FakeFault fault;
  final FakeOp op;
  int remaining;
}

final class _Rejection {
  const _Rejection(this.test, this.code);
  final bool Function(ChunkWrite chunk) test;
  final SyncErrorCode code;
}

final class _OfflineListener {
  _OfflineListener(this.callback);
  final void Function() callback;
}
