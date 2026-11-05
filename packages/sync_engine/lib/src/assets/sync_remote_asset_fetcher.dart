// Contract 7.2.20 verbatim (imports note_core as core).
import 'package:note_core/note_core.dart' as core;

import 'sync_asset_service.dart';

/// core.RemoteAssetFetcher over SyncAssetService (M4 wiring by INFRA).
final class SyncRemoteAssetFetcher implements core.RemoteAssetFetcher {
  SyncRemoteAssetFetcher(SyncAssetService service);

  @override
  Future<bool> ensureLocal(core.AssetId id) =>
      throw UnimplementedError('SYNC T12');

  @override
  Stream<core.RemoteAssetProgress> watch(core.AssetId id) =>
      throw UnimplementedError('SYNC T12');
}
