import 'package:flutter/material.dart';

/// Temporary dummy data for CleanSpot profile, rewards, and reports screens.
///
/// Designed to match Firestore schema field names (`title`, `description`,
/// `cost`, `code`, `available`) for effortless migration to real backend collections.

/// Represents a mockup user profile.
class DummyUser {
  final String name;
  final String email;
  final String? photoUrl;
  final int points;

  const DummyUser({
    this.name = 'Chathuranga Sandaruwan',
    this.email = 'chathuranga@example.com',
    this.photoUrl,
    this.points = 120,
  });

  // Firestore schema compatibility aliases
  String get displayName => name;
  int get pointsBalance => points;
}

/// Default active dummy user instance.
const DummyUser dummyUser = DummyUser();

/// Represents a reward coupon redeemable with user points.
class DummyCoupon {
  final String id;
  final String title;
  final String description;
  final int cost;
  final String code;
  final IconData icon;
  final bool available;

  const DummyCoupon({
    required this.id,
    required this.title,
    required this.description,
    required this.cost,
    required this.code,
    required this.icon,
    this.available = true,
  });

  // Firestore schema compatibility aliases
  int get pointsCost => cost;
  String get value => description;
  String get status => available ? 'available' : 'redeemed';
}

/// 5 sample reward coupons.
const List<DummyCoupon> dummyCoupons = [
  DummyCoupon(
    id: 'coupon-eco-20',
    title: 'Eco Discount',
    description: 'A sample discount reward',
    cost: 20,
    code: 'ECO20',
    icon: Icons.confirmation_number_outlined,
    available: true,
  ),
  DummyCoupon(
    id: 'coupon-green-30',
    title: 'Green Shopper',
    description: 'A sustainable shopping reward',
    cost: 30,
    code: 'GREEN30',
    icon: Icons.shopping_bag_outlined,
    available: true,
  ),
  DummyCoupon(
    id: 'coupon-shield-45',
    title: 'Community Shield',
    description: 'Repellent and mosquito safety kit voucher',
    cost: 45,
    code: 'SHIELD45',
    icon: Icons.verified_user_outlined,
    available: true,
  ),
  DummyCoupon(
    id: 'coupon-award-60',
    title: 'Clean Champion',
    description: 'Eco-certified home garden supplies voucher',
    cost: 60,
    code: 'CHAMP60',
    icon: Icons.military_tech_outlined,
    available: true,
  ),
  DummyCoupon(
    id: 'coupon-transit-40',
    title: 'Green Transit Pass',
    description: 'Low-emission public transport fare discount',
    cost: 40,
    code: 'TRANSIT40',
    icon: Icons.directions_bus_outlined,
    available: true,
  ),
];

/// Represents a submitted dengue mosquito breeding site report.
class DummyReport {
  final String id;
  final String type;
  final String location;
  final String dateText;
  final String status;
  final String? imageUrl;
  final String? aiNote;
  final String? pointsText;

  const DummyReport({
    this.id = '',
    required this.type,
    required this.location,
    required this.dateText,
    required this.status,
    this.imageUrl,
    this.aiNote,
    this.pointsText,
  });

  // Helper flags for UI filters and badges
  bool get isValid =>
      status.toLowerCase() == 'valid' ||
      status.toLowerCase().contains('valid') ||
      status.toLowerCase().contains('approved');
  bool get isPending => status.toLowerCase().contains('pending');
  bool get isChecking => status.toLowerCase().contains('checking');
  bool get isRejected =>
      status.toLowerCase().contains('rejected') ||
      status.toLowerCase().contains('detail');
  bool get isInProgress => isPending || isChecking;
  bool get isReviewed => isValid || status.toLowerCase().contains('reviewed');
}

/// 4 sample breeding site reports matching Figma / Mockup Page 5 ("My Reports").
const List<DummyReport> dummyReports = [
  DummyReport(
    id: 'report-1',
    type: 'Discarded tyre',
    location: 'Sample campus garden',
    dateText: '13 Oct · 9:41 AM',
    status: 'Valid',
    imageUrl:
        'https://images.unsplash.com/photo-1584467735871-8e85353a8413?w=400&auto=format&fit=crop&q=80',
    aiNote: 'AI: Standing water detected.',
    pointsText: '+10 points',
  ),
  DummyReport(
    id: 'report-2',
    type: 'Open container',
    location: 'Sample volunteer centre',
    dateText: '13 Oct · 10:15 AM',
    status: 'Pending',
    imageUrl:
        'https://images.unsplash.com/photo-1578328819058-b69f3a3b0f6b?w=400&auto=format&fit=crop&q=80',
    aiNote: 'AI: Queued for validation.',
    pointsText: 'Not awarded yet',
  ),
  DummyReport(
    id: 'report-3',
    type: 'Blocked drain',
    location: 'Sample community lane',
    dateText: '13 Oct · 10:00 AM',
    status: 'Checking',
    imageUrl:
        'https://images.unsplash.com/photo-1542601906990-b4d3fb778b09?w=400&auto=format&fit=crop&q=80',
    aiNote: 'AI: Checking water and duplicates.',
    pointsText: 'Not awarded yet',
  ),
  DummyReport(
    id: 'report-4',
    type: 'Containers',
    location: 'Sample volunteer centre',
    dateText: '8 Oct · 11:20 AM',
    status: 'Rejected',
    imageUrl:
        'https://images.unsplash.com/photo-1578328819058-b69f3a3b0f6b?w=400&auto=format&fit=crop&q=80',
    aiNote: 'AI: Duplicate of an existing report.',
    pointsText: '0 points',
  ),
];

/// Represents a coupon already redeemed by the user.
class DummyRedemption {
  final String id;
  final String title;
  final String description;
  final int points;
  final String code;
  final String dateText;
  final IconData icon;

  const DummyRedemption({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.code,
    required this.dateText,
    this.icon = Icons.confirmation_number_outlined,
  });

  int get cost => points;
}

/// Redeemed coupon list for the user.
const List<DummyRedemption> dummyRedemptions = [
  DummyRedemption(
    id: 'redemption-1',
    title: 'Eco Discount',
    description: 'A sample discount reward',
    points: 20,
    code: 'ECO20',
    dateText: '12 Oct 2026',
    icon: Icons.confirmation_number_outlined,
  ),
];
