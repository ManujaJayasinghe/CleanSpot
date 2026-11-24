class CouponModel {
  final String id;
  final String title;
  final String description;
  final int cost;
  final String code;
  final bool available;
  final int stock;
  final List<String> codes;

  const CouponModel({
    required this.id,
    required this.title,
    required this.description,
    required this.cost,
    required this.code,
    required this.available,
    this.stock = 1,
    this.codes = const [],
  });

  factory CouponModel.fromMap(String id, Map<String, dynamic> map) {
    // Gracefully handle both team schema (cost, available) and any legacy keys (pointsCost, status, value)
    final costVal = (map['cost'] ?? map['pointsCost'] as num?)?.toInt() ?? 0;
    final availableVal = map['available'] is bool
        ? map['available'] as bool
        : (map['status'] == 'available' || map['available'] == null);
    final descVal = map['description'] as String? ?? map['value'] as String? ?? '';
    final titleVal = map['title'] as String? ?? (descVal.isNotEmpty ? descVal : 'Coupon');
    final codeVal = map['code'] as String? ?? '';

    // Handle pool of codes or fallback to single code
    final rawCodes = map['codes'];
    List<String> codesList = [];
    if (rawCodes is List) {
      codesList = rawCodes.map((e) => e.toString()).toList();
    } else if (codeVal.isNotEmpty) {
      codesList = [codeVal];
    }

    final stockVal = (map['stock'] as num?)?.toInt() ??
        (codesList.isNotEmpty ? codesList.length : (availableVal ? 1 : 0));

    return CouponModel(
      id: id,
      title: titleVal,
      description: descVal,
      cost: costVal,
      code: codeVal.isNotEmpty ? codeVal : (codesList.isNotEmpty ? codesList.first : ''),
      available: availableVal && stockVal > 0,
      stock: stockVal,
      codes: codesList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'cost': cost,
      'code': code,
      'available': available && stock > 0,
      'stock': stock,
      'codes': codes,
      // Retain backwards compatibility fields
      'value': description,
      'pointsCost': cost,
      'status': (available && stock > 0) ? 'available' : 'redeemed',
    };
  }

  // Backwards compatibility getters
  bool get hasStock => stock > 0 && available;
  String get value => description;
  int get pointsCost => cost;
  String get status => (available && stock > 0) ? 'available' : 'redeemed';
}
