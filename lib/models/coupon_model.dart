class CouponModel {
  final String id;
  final String title;
  final String description;
  final int cost;
  final String code;
  final bool available;

  const CouponModel({
    required this.id,
    required this.title,
    required this.description,
    required this.cost,
    required this.code,
    required this.available,
  });

  factory CouponModel.fromMap(String id, Map<String, dynamic> map) {
    // Gracefully handle both team schema (cost, available) and any legacy keys (pointsCost, status, value)
    final costVal = (map['cost'] ?? map['pointsCost'] as num?)?.toInt() ?? 0;
    final availableVal = map['available'] is bool
        ? map['available'] as bool
        : (map['status'] == 'available' || map['available'] == null);
    final descVal = map['description'] as String? ?? map['value'] as String? ?? '';
    final titleVal = map['title'] as String? ?? (descVal.isNotEmpty ? descVal : 'Coupon');

    return CouponModel(
      id: id,
      title: titleVal,
      description: descVal,
      cost: costVal,
      code: map['code'] as String? ?? '',
      available: availableVal,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'cost': cost,
      'code': code,
      'available': available,
      // Retain backwards compatibility fields if needed by any teammate
      'value': description,
      'pointsCost': cost,
      'status': available ? 'available' : 'redeemed',
    };
  }

  // Backwards compatibility getters
  String get value => description;
  int get pointsCost => cost;
  String get status => available ? 'available' : 'redeemed';
}
