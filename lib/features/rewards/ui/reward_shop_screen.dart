import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/theme_proposal.dart';
import '../../../models/coupon_model.dart';
import '../../../services/firestore_service.dart';
import '../../profile/widgets/widgets.dart';
import 'coupon_dialog.dart';
import 'widgets/coupon_card.dart';

/// Reward Shop screen displaying available coupons from Firestore,
/// live user points balance, and atomic Firestore redemption.
class RewardShopScreen extends StatefulWidget {
  const RewardShopScreen({super.key});

  @override
  State<RewardShopScreen> createState() => _RewardShopScreenState();
}

class _RewardShopScreenState extends State<RewardShopScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isRedeeming = false;

  IconData _iconForTitle(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('coffee') || lower.contains('cafe')) {
      return Icons.local_cafe_outlined;
    } else if (lower.contains('plant') || lower.contains('seed')) {
      return Icons.yard_outlined;
    } else if (lower.contains('soap') || lower.contains('spray') || lower.contains('kit')) {
      return Icons.clean_hands_outlined;
    } else if (lower.contains('bus') || lower.contains('transit')) {
      return Icons.directions_bus_outlined;
    } else if (lower.contains('tea')) {
      return Icons.emoji_food_beverage_outlined;
    }
    return Icons.local_offer_outlined;
  }

  Future<void> _handleRedeem(CouponModel coupon, int currentBalance) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to redeem coupons.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (currentBalance < coupon.cost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not enough points to redeem this coupon.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (_isRedeeming) return;
    setState(() => _isRedeeming = true);

    try {
      final code = await _firestoreService.redeemCoupon(
        uid: user.uid,
        coupon: coupon,
      );

      if (!mounted) return;
      setState(() => _isRedeeming = false);

      showCouponDialog(context, title: coupon.title, code: code);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRedeeming = false);

      String msg = 'Failed to redeem coupon: $e';
      if (e.toString().contains('not_enough_points')) {
        msg = 'Not enough points for this coupon.';
      } else if (e.toString().contains('coupon_already_redeemed')) {
        msg = 'This coupon has already been redeemed.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder(
          stream: uid.isNotEmpty ? _firestoreService.watchUser(uid) : null,
          builder: (context, userSnap) {
            final userModel = userSnap.data;
            final points = userModel?.pointsBalance ?? 0;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Screen Title & Subtitle
                  Text(
                    'Rewards',
                    style: (textTheme.headlineMedium ?? AppTypography.title).copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Good actions deserve recognition.',
                    style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Points Card (YOUR BALANCE)
                  PointsCard(
                    label: 'YOUR BALANCE',
                    points: points,
                    caption: 'Keep making a difference.',
                  ),
                  const SizedBox(height: 24),

                  // Section Heading
                  Text(
                    'Redeem your points',
                    style: (textTheme.titleLarge ?? AppTypography.heading).copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Stream coupons from Firestore
                  StreamBuilder<List<CouponModel>>(
                    stream: _firestoreService.watchAvailableCoupons(),
                    builder: (context, couponSnap) {
                      if (couponSnap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final coupons = couponSnap.data ?? [];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${coupons.length} rewards available · Scroll to explore all',
                            style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (coupons.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.card_giftcard_outlined,
                                    size: 48,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No rewards available at the moment',
                                    style: TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Check back soon for new community sponsor offers!',
                                    style: TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: coupons.length,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 0.65,
                              ),
                              itemBuilder: (context, index) {
                                final coupon = coupons[index];
                                return CouponCard(
                                  coupon: coupon,
                                  userPoints: points,
                                  icon: _iconForTitle(coupon.title),
                                  onRedeem: () => _handleRedeem(coupon, points),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
