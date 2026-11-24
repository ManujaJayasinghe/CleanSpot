import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String displayName;
  final int pointsBalance;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.pointsBalance,
    required this.createdAt,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    // Gracefully handle either 'points' (team schema) or 'pointsBalance'
    final pointsVal = (map['points'] ?? map['pointsBalance'] as num?)?.toInt() ?? 0;

    return UserModel(
      uid: uid,
      displayName: map['displayName'] as String? ?? map['name'] as String? ?? '',
      pointsBalance: pointsVal,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'name': displayName,
      'points': pointsBalance,
      'pointsBalance': pointsBalance,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // Alias getter for points
  int get points => pointsBalance;
}
