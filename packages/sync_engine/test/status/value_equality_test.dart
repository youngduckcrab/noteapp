// Value equality of the seven status value classes (contract 7.2.20 v1.2, SYNC-2-8):
// same values → == and the same hashCode; any one field different → !=; an equal issues
// list in another object → ==; AuthState.lastError compares by identity.
// (statusStream not repeating a value is checked with the engine, T10.)
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';

/// [make] builds the base value; each of [variants] builds it with one field changed.
void checkValue<T>(
  String name,
  T Function() make,
  Map<String, T Function()> variants,
) {
  group(name, () {
    test('same values: == and same hashCode', () {
      final a = make(), b = make();
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
    for (final MapEntry(key: field, value: variant) in variants.entries) {
      test('$field differs: !=', () => expect(variant(), isNot(make())));
    }
  });
}

SyncIssue issue({
  SyncIssueCode code = SyncIssueCode.clockSkew,
  String message = 'off',
  int firstAt = 1,
  int lastAt = 2,
  int count = 1,
  EntityRef? ref,
  String? assetId,
  String? nodeId = 'b2b2b2b2b2b2b2b2',
}) => SyncIssue(
  code: code,
  message: message,
  firstAt: firstAt,
  lastAt: lastAt,
  count: count,
  ref: ref,
  assetId: assetId,
  nodeId: nodeId,
);

const AuthUser user = AuthUser(
  uid: 'u1',
  email: 'a@b.c',
  displayName: 'A',
  photoUrl: 'p',
);

SyncStatus status({
  SyncPhase phase = SyncPhase.live,
  SyncDisplayState display = SyncDisplayState.done,
  AuthUser? user = user,
  int pendingUploads = 1,
  int quarantinedUploads = 0,
  bool isPushing = false,
  InitialSyncProgress? initialSync,
  AssetTransferSummary assets = AssetTransferSummary.idle,
  int? lastSyncedAt = 10,
  int? nextRetryAt,
  List<SyncIssue>? issues,
  bool isOnline = true,
  Duration? clockSkew = const Duration(seconds: 3),
}) => SyncStatus(
  phase: phase,
  display: display,
  user: user,
  pendingUploads: pendingUploads,
  quarantinedUploads: quarantinedUploads,
  isPushing: isPushing,
  initialSync: initialSync,
  assets: assets,
  lastSyncedAt: lastSyncedAt,
  nextRetryAt: nextRetryAt,
  issues: issues ?? [issue()],
  isOnline: isOnline,
  clockSkew: clockSkew,
);

void main() {
  checkValue('SyncStatus', status, {
    'phase': () => status(phase: SyncPhase.catchingUp),
    'display': () => status(display: SyncDisplayState.inProgress),
    'user': () => status(user: const AuthUser(uid: 'u2')),
    'pendingUploads': () => status(pendingUploads: 2),
    'quarantinedUploads': () => status(quarantinedUploads: 1),
    'isPushing': () => status(isPushing: true),
    'initialSync': () => status(
      initialSync: const InitialSyncProgress(
        chunksApplied: 1,
        recordsApplied: 1,
        startedAt: 0,
      ),
    ),
    'assets': () =>
        status(assets: const AssetTransferSummary(uploadsPending: 1)),
    'lastSyncedAt': () => status(lastSyncedAt: 11),
    'nextRetryAt': () => status(nextRetryAt: 5),
    'issues': () => status(issues: [issue(count: 2)]),
    'isOnline': () => status(isOnline: false),
    'clockSkew': () => status(clockSkew: const Duration(seconds: 4)),
  });

  test('SyncStatus: an equal issues list in another object is ==', () {
    final a = status(
      issues: [
        issue(),
        issue(code: SyncIssueCode.needsAppUpdate),
      ],
    );
    final b = status(
      issues: [
        issue(),
        issue(code: SyncIssueCode.needsAppUpdate),
      ],
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  checkValue('SyncIssue', issue, {
    'code': () => issue(code: SyncIssueCode.clockSkewWarning),
    'message': () => issue(message: 'other'),
    'firstAt': () => issue(firstAt: 0),
    'lastAt': () => issue(lastAt: 3),
    'count': () => issue(count: 2),
    'ref': () => issue(ref: const EntityRef(EntityKind.note, 'n1')),
    'assetId': () => issue(assetId: 'a1'),
    'nodeId': () => issue(nodeId: 'c3c3c3c3c3c3c3c3'),
  });

  AuthUser makeUser({
    String uid = 'u1',
    String? email = 'a@b.c',
    String? displayName = 'A',
    String? photoUrl = 'p',
  }) => AuthUser(
    uid: uid,
    email: email,
    displayName: displayName,
    photoUrl: photoUrl,
  );
  checkValue('AuthUser', makeUser, {
    'uid': () => makeUser(uid: 'u2'),
    'email': () => makeUser(email: 'x@b.c'),
    'displayName': () => makeUser(displayName: 'B'),
    'photoUrl': () => makeUser(photoUrl: 'q'),
  });

  const failure = SignInException(SignInErrorCode.cancelled, 'closed');
  AuthState authState({
    AuthStatus status = AuthStatus.signedOut,
    AuthUser? user,
    SignInException? lastError = failure,
  }) => AuthState(status: status, user: user, lastError: lastError);
  checkValue('AuthState', authState, {
    'status': () => authState(status: AuthStatus.signingIn),
    'user': () => authState(user: makeUser()),
    'lastError': () => authState(lastError: null),
  });

  test('AuthState.lastError compares by identity: another exception object '
      'with the same values is !=', () {
    // Not const: two distinct objects.
    final e1 = SignInException(SignInErrorCode.cancelled, 'closed'.toString());
    final e2 = SignInException(SignInErrorCode.cancelled, 'closed'.toString());
    expect(
      AuthState(status: AuthStatus.signedOut, lastError: e1),
      isNot(AuthState(status: AuthStatus.signedOut, lastError: e2)),
    );
    expect(
      AuthState(status: AuthStatus.signedOut, lastError: e1),
      AuthState(status: AuthStatus.signedOut, lastError: e1),
    );
  });

  AssetAvailability availability({
    String id = 'a1',
    AssetAvailabilityState state = AssetAvailabilityState.downloading,
    int? receivedBytes = 1,
    int? totalBytes = 2,
    SyncIssue? error,
  }) => AssetAvailability(
    id: id,
    state: state,
    receivedBytes: receivedBytes,
    totalBytes: totalBytes,
    error: error,
  );
  checkValue('AssetAvailability', availability, {
    'id': () => availability(id: 'a2'),
    'state': () => availability(state: AssetAvailabilityState.local),
    'receivedBytes': () => availability(receivedBytes: 2),
    'totalBytes': () => availability(totalBytes: 3),
    'error': () => availability(error: issue()),
  });

  AssetTransferSummary summary([int changed = -1]) => AssetTransferSummary(
    uploadsPending: changed == 0 ? 9 : 1,
    uploadBytesDone: changed == 1 ? 9 : 2,
    uploadBytesTotal: changed == 2 ? 9 : 3,
    downloadsActive: changed == 3 ? 9 : 4,
    downloadBytesDone: changed == 4 ? 9 : 5,
    downloadBytesTotal: changed == 5 ? 9 : 6,
  );
  checkValue('AssetTransferSummary', summary, {
    for (final (i, name) in [
      'uploadsPending',
      'uploadBytesDone',
      'uploadBytesTotal',
      'downloadsActive',
      'downloadBytesDone',
      'downloadBytesTotal',
    ].indexed)
      name: () => summary(i),
  });

  InitialSyncProgress progress([int changed = -1]) => InitialSyncProgress(
    chunksApplied: changed == 0 ? 9 : 1,
    estimatedTotalChunks: changed == 1 ? null : 2,
    recordsApplied: changed == 2 ? 9 : 3,
    startedAt: changed == 3 ? 9 : 4,
  );
  checkValue('InitialSyncProgress', progress, {
    for (final (i, name) in [
      'chunksApplied',
      'estimatedTotalChunks',
      'recordsApplied',
      'startedAt',
    ].indexed)
      name: () => progress(i),
  });
}
