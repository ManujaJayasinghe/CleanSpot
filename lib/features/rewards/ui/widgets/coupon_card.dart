import 'package:flutter/material.dart';

import '../../../../app/theme_proposal.dart';
import '../../../../models/coupon_model.dart';

/// A card representing a reward coupon in the shop grid.
class CouponCard extends StatelessWidget {
  final CouponModel coupon;
  final int userPoints;
  final VoidCallback? onRedeem;
  final IconData icon;

  const CouponCard({
    super.key,
    required this.coupon,
    required this.userPoints,
    this.onRedeem,
    this.icon = Icons.local_offer_outlined,
  });

  bool get canRedeem => userPoints >= coupon.cost;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EDE8), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mint icon box
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 22,
              color: const Color(0xFF1B5E3B),
            ),
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            coupon.title,
            style: (textTheme.titleSmall ?? AppTypography.heading).copyWith(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),

          // Short description
          Expanded(
            child: Text(
              coupon.description,
              style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),

          // Cost in bold dark green
          Text(
            '${coupon.cost} points',
            style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF145A32),
            ),
          ),
          const SizedBox(height: 10),

          // Full-width Redeem button
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: canRedeem ? onRedeem : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canRedeem
                    ? const Color(0xFF1E7E44)
                    : AppColors.border.withValues(alpha: 0.6),
                foregroundColor:
                    canRedeem ? Colors.white : AppColors.textSecondary,
                disabledBackgroundColor:
                    AppColors.border.withValues(alpha: 0.6),
                disabledForegroundColor: AppColors.textSecondary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                canRedeem ? 'Redeem' : 'Not enough points',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: canRedeem ? 14 : 11,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
