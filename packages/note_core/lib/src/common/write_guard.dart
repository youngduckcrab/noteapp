// lib/src/common/write_guard.dart (internal) — the HandwritingRepository.update transform
// zone (m5-7/02-core 6.9.4). The transform is synchronous and pure; a store write called from
// inside it would wait for the same queue (or slip outside the one transaction), so every
// store write path checks [inUpdateTransform] and fails at once with [writeInTransformError]
// (like the 1st-round re-entry rule N-2). Used by the fake and the SQLite store.
import 'dart:async';

/// Set (true) in the zone of a running HandwritingRepository.update transform.
const Object kInTransformZoneKey = #noteCoreHandwritingTransform;

/// Whether the current code runs inside an update transform (or a callback it scheduled).
bool get inUpdateTransform => Zone.current[kInTransformZoneKey] == true;

/// The error of a store write called from inside an update transform.
StateError writeInTransformError() => StateError(
  'A store write was called from inside a HandwritingRepository.update '
  'transform (it must be synchronous and pure)',
);

/// Runs [transform] synchronously in the transform zone.
T runUpdateTransform<T>(T Function() transform) =>
    runZoned(transform, zoneValues: {kInTransformZoneKey: true});
