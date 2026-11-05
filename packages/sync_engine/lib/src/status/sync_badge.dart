// Contract 7.2.20 verbatim (imports note_core as core).
import 'package:note_core/note_core.dart' as core;

import 'sync_status.dart';

/// For the app shell's syncBadgeProvider override (M4).
core.SyncBadge syncBadgeOf(SyncStatus status) {
  String? issueCode;
  for (final issue in status.issues) {
    if (issue.isBlocking) {
      issueCode = issue.code.name;
      break;
    }
  }
  return core.SyncBadge(
    display: status.display,
    pendingChanges: status.pendingUploads,
    lastSyncedAt: status.lastSyncedAt,
    issueCode: issueCode,
  );
}
