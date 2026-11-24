import 'package:cloud_firestore/cloud_firestore.dart';

/// Roles stored in `users/{uid}.role`. Anything else is treated as a normal user.
const String kRoleUser = 'user';
const String kRoleAdmin = 'admin';
const String kRoleAuthority = 'authority';
const List<String> kUserRoles = [kRoleUser, kRoleAdmin, kRoleAuthority];

/// A stored role, or 'user' when it is missing or not one of [kUserRoles].
String normalizeRole(Object? stored) =>
    stored is String && kUserRoles.contains(stored) ? stored : kRoleUser;

class UserModel {
  final String uid;
  final String displayName;
  final int pointsBalance;
  final DateTime createdAt;

  /// 'user' (default), 'admin' or 'authority'. Old documents without it are
  /// normal users. Only an admin can change it (see firestore.rules).
  final String role;

  /// A blocked user is signed out of the app and cannot save anything. Old
  /// documents without it are not blocked.
  final bool blocked;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.pointsBalance,
    required this.createdAt,
    this.role = kRoleUser,
    this.blocked = false,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    // Gracefully handle either 'points' (team schema) or 'pointsBalance'
    final pointsVal = (map['points'] ?? map['pointsBalance'] as num?)?.toInt() ?? 0;

    return UserModel(
      uid: uid,
      displayName: map['displayName'] as String? ?? map['name'] as String? ?? '',
      pointsBalance: pointsVal,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      role: normalizeRole(map['role']),
      blocked: map['blocked'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'name': displayName,
      'points': pointsBalance,
      'pointsBalance': pointsBalance,
      'createdAt': Timestamp.fromDate(createdAt),
      'role': role,
      'blocked': blocked,
    };
  }

  // Alias getter for points
  int get points => pointsBalance;

  bool get isAdmin => role == kRoleAdmin;
  bool get isAuthority => role == kRoleAuthority;
}
