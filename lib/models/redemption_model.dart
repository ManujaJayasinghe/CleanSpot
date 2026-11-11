import 'package:cloud_firestore/cloud_firestore.dart';

class RedemptionModel {
  final String id;
  final String uid;
  final String couponId;
  final String code;
  final String title;
  final String description;
  final int cost;
  final DateTime redeemedAt;

  const RedemptionModel({
    required this.id,
    required this.uid,
    required this.couponId,
    required this.code,
    this.title = '',
    this.description = '',
    this.cost = 0,
    required this.redeemedAt,
  });

  factory RedemptionModel.fromMap(String id, Map<String, dynamic> map) {
    return RedemptionModel(
      id: id,
      uid: map['uid'] as String? ?? '',
      couponId: map['couponId'] as String? ?? '',
      code: map['code'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      cost: (map['cost'] as num?)?.toInt() ?? 0,
      redeemedAt: (map['redeemedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'couponId': couponId,
      'code': code,
      'title': title,
      'description': description,
      'cost': cost,
      'redeemedAt': Timestamp.fromDate(redeemedAt),
    };
  }
}

