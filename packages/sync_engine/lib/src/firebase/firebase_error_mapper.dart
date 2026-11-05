import '../common/errors.dart';

/// FirebaseException / FirebaseAuthException / TimeoutException → SyncBackendException.
SyncBackendException mapFirebaseError(Object error, {StackTrace? stackTrace}) =>
    throw UnimplementedError('SYNC T17');

SignInException mapSignInError(Object error) =>
    throw UnimplementedError('SYNC T17');
