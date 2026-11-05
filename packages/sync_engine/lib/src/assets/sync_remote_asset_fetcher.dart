// Contract 7.2.20 verbatim (imports note_core as core).
import 'dart:async';

import 'package:note_core/note_core.dart' as core;

import 'sync_asset_service.dart';

/// core.RemoteAssetFetcher over SyncAssetService (M4 wiring by INFRA).
final class SyncRemoteAssetFetcher implements core.RemoteAssetFetcher {
  SyncRemoteAssetFetcher(SyncAssetService service) : _service = service;

  final SyncAssetService _service;

  /// SyncAssetService.ensureLocal with visible priority (6.9.3).
  @override
  Future<bool> ensureLocal(core.AssetId id) =>
      _service.ensureLocal(id, priority: AssetPriority.visible);

  /// SyncAssetService.watch mapped by the 6.9.3 table; consecutive equal values are
  /// dropped and the stream closes after `local`.
  @override
  Stream<core.RemoteAssetProgress> watch(core.AssetId id) =>
      Stream.multi((controller) {
        core.RemoteAssetProgress? last;
        var closed = false;
        late final StreamSubscription<AssetAvailability> sub;
        void finish() {
          if (closed) return;
          closed = true;
          unawaited(sub.cancel());
          unawaited(controller.close());
        }

        sub = _service
            .watch(id)
            .listen(
              (availability) {
                if (closed) return;
                final progress = _progressOf(availability);
                final previous = last;
                if (previous != null &&
                    previous.state == progress.state &&
                    previous.received == progress.received &&
                    previous.total == progress.total) {
                  return;
                }
                last = progress;
                controller.add(progress);
                if (progress.state == core.RemoteAssetState.local) finish();
              },
              onError: controller.addError,
              onDone: finish,
            );
        // The cancel future is not returned: done would wait for it.
        controller.onCancel = () {
          closed = true;
          unawaited(sub.cancel());
        };
      });

  static core.RemoteAssetProgress _progressOf(AssetAvailability a) =>
      switch (a.state) {
        AssetAvailabilityState.local => const core.RemoteAssetProgress(
          core.RemoteAssetState.local,
        ),
        AssetAvailabilityState.downloading => core.RemoteAssetProgress(
          core.RemoteAssetState.downloading,
          received: a.receivedBytes,
          total: a.totalBytes,
        ),
        AssetAvailabilityState.queued => core.RemoteAssetProgress(
          core.RemoteAssetState.downloading,
          received: 0,
          total: a.totalBytes,
        ),
        AssetAvailabilityState.remoteReady ||
        AssetAvailabilityState.waitingForUpload ||
        AssetAvailabilityState.unknown => const core.RemoteAssetProgress(
          core.RemoteAssetState.waiting,
        ),
        AssetAvailabilityState.offline => const core.RemoteAssetProgress(
          core.RemoteAssetState.offline,
        ),
        AssetAvailabilityState.failed => const core.RemoteAssetProgress(
          core.RemoteAssetState.failed,
        ),
        AssetAvailabilityState.syncDisabled => const core.RemoteAssetProgress(
          core.RemoteAssetState.unavailable,
        ),
      };
}
