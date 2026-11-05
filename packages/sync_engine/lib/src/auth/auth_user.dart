import 'package:meta/meta.dart';

@immutable
final class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  /// Firebase uid, 1..128 chars.
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  /// (contract 7.2.20 v1.2 — C12-04) Value equality over the four fields: one of the seven
  /// value-equality classes, the type of AuthState.user / SyncStatus.user (7.4.4).
  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(uid, email, displayName, photoUrl);

  @override
  String toString() => 'AuthUser($uid)';
}
