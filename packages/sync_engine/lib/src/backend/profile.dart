import 'package:meta/meta.dart';

import '../common/server_cursor.dart';
import '../config.dart';

@immutable
final class UserProfile {
  const UserProfile({required this.uid, this.email, this.displayName});
  final String uid;
  final String? email, displayName;
}

@immutable
final class DeviceInfo {
  const DeviceInfo({
    required this.nodeId,
    required this.platform,
    required this.appVersion,
    this.cursor,
  });
  final String nodeId;
  final DevicePlatform platform;
  final String appVersion;

  /// Last applied; for future tombstone GC.
  final ServerCursor? cursor;
}
