// T17: Firebase errors → SyncBackendException (6.4.6: Firestore's 14 status codes,
// TimeoutException → deadlineExceeded) and FirebaseAuthException → SignInException (6.10.1).
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/firebase.dart';
import 'package:sync_engine/sync_engine.dart';

FirebaseException _firestore(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code, message: 'm');

void main() {
  group('mapFirebaseError', () {
    test('the 14 Firestore status codes', () {
      const table = {
        'unavailable': SyncErrorCode.unavailable,
        'deadline-exceeded': SyncErrorCode.deadlineExceeded,
        'permission-denied': SyncErrorCode.permissionDenied,
        'unauthenticated': SyncErrorCode.unauthenticated,
        'resource-exhausted': SyncErrorCode.resourceExhausted,
        'invalid-argument': SyncErrorCode.invalidArgument,
        'aborted': SyncErrorCode.aborted,
        'not-found': SyncErrorCode.notFound,
        'already-exists': SyncErrorCode.alreadyExists,
        'failed-precondition': SyncErrorCode.failedPrecondition,
        'cancelled': SyncErrorCode.cancelled,
        'internal': SyncErrorCode.internal,
        'data-loss': SyncErrorCode.dataLoss,
        'unknown': SyncErrorCode.unknown,
      };
      expect(table, hasLength(14));
      for (final MapEntry(key: code, value: expected) in table.entries) {
        final error = _firestore(code);
        final mapped = mapFirebaseError(error);
        expect(mapped.code, expected, reason: code);
        expect(mapped.cause, same(error));
        expect(mapped.message, contains(code));
        // The web SDK's prefixed form.
        expect(mapFirebaseError(_firestore('firestore/$code')).code, expected);
      }
    });

    test('TimeoutException → deadlineExceeded; Auth and Storage codes; '
        'anything else → unknown; a SyncBackendException passes through', () {
      expect(
        mapFirebaseError(TimeoutException('slow')).code,
        SyncErrorCode.deadlineExceeded,
      );
      expect(
        mapFirebaseError(FirebaseAuthException(code: 'network-request-failed'))
            .code,
        SyncErrorCode.network,
      );
      expect(
        mapFirebaseError(FirebaseAuthException(code: 'user-token-expired'))
            .code,
        SyncErrorCode.unauthenticated,
      );
      expect(
        mapFirebaseError(
          FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'),
        ).code,
        SyncErrorCode.permissionDenied,
      );
      expect(
        mapFirebaseError(
          FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
          ),
        ).code,
        SyncErrorCode.notFound,
      );
      expect(
        mapFirebaseError(
          FirebaseException(plugin: 'firebase_storage', code: 'quota-exceeded'),
        ).code,
        SyncErrorCode.resourceExhausted,
      );
      expect(
        mapFirebaseError(_firestore('something-new')).code,
        SyncErrorCode.unknown,
      );
      final odd = StateError('odd');
      expect(mapFirebaseError(odd).code, SyncErrorCode.unknown);
      expect(mapFirebaseError(odd).cause, same(odd));
      const own = SyncBackendException(SyncErrorCode.aborted, 'x');
      expect(mapFirebaseError(own), same(own));
    });
  });

  group('mapSignInError', () {
    test('FirebaseAuthException codes of popup / redirect sign-in', () {
      const table = {
        'popup-closed-by-user': SignInErrorCode.cancelled,
        'cancelled-popup-request': SignInErrorCode.cancelled,
        'user-cancelled': SignInErrorCode.cancelled,
        'popup-blocked': SignInErrorCode.popupBlocked,
        'network-request-failed': SignInErrorCode.network,
        'operation-not-supported-in-this-environment':
            SignInErrorCode.unsupportedPlatform,
        'user-disabled': SignInErrorCode.accountDisabled,
        'operation-not-allowed': SignInErrorCode.misconfigured,
        'unauthorized-domain': SignInErrorCode.misconfigured,
        'invalid-api-key': SignInErrorCode.misconfigured,
        'internal-error': SignInErrorCode.unknown,
      };
      for (final MapEntry(key: code, value: expected) in table.entries) {
        final error = FirebaseAuthException(code: code, message: 'm');
        final mapped = mapSignInError(error);
        expect(mapped.code, expected, reason: code);
        expect(mapped.cause, same(error));
        expect(
          mapSignInError(FirebaseAuthException(code: 'auth/$code')).code,
          expected,
        );
      }
    });

    test('others: TimeoutException → network, anything else → unknown, a '
        'SignInException passes through', () {
      expect(
        mapSignInError(TimeoutException('slow')).code,
        SignInErrorCode.network,
      );
      expect(mapSignInError(StateError('x')).code, SignInErrorCode.unknown);
      const own = SignInException(SignInErrorCode.cancelled, 'x');
      expect(mapSignInError(own), same(own));
    });
  });
}
