import 'package:flutter/material.dart';

import '../../../app/theme_proposal.dart';
import '../../../models/coupon_model.dart';
import '../../../services/firestore_service.dart';

/// Coupons tab allowing admins to view inventory, add new coupons (with stock/code pools),
/// and delete existing coupons.
class AdminCouponsTab extends StatelessWidget {
  final FirestoreService firestoreService;

  const AdminCouponsTab({
    super.key,
    required this.firestoreService,
  });

  Future<void> _showAddCouponDialog(BuildContext context) async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final costController = TextEditingController(text: '100');
    final codesController = TextEditingController();
    final stockController = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    // Update stock when codes change if comma-separated
    codesController.addListener(() {
      final text = codesController.text.trim();
      if (text.contains(',')) {
        final list = text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (list.isNotEmpty) {
          stockController.text = list.length.toString();
        }
      }
    });

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Add New Coupon',
            style: AppTypography.heading.copyWith(fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'e.g. 15% Eco Grocery Discount',
                    ),
                    validator: (val) =>
                        (val == null || val.trim().isEmpty) ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description / Value',
                      hintText: 'e.g. Valid on all organic products',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: costController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Points Cost *',
                            suffixText: 'pts',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Cost is required';
                            final parsed = int.tryParse(val.trim());
                            if (parsed == null || parsed < 0) return 'Invalid number';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: stockController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Stock *',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Stock is required';
                            final parsed = int.tryParse(val.trim());
                            if (parsed == null || parsed < 0) return 'Invalid';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: codesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Promo Code(s) *',
                      hintText: 'e.g. CLEAN2026 or CODE1, CODE2, CODE3',
                      helperText: 'Separate multiple codes with commas for code pool',
                    ),
                    validator: (val) =>
                        (val == null || val.trim().isEmpty) ? 'At least one code is required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (formKey.currentState?.validate() != true) return;

                      setDialogState(() => isSubmitting = true);

                      final rawCodes = codesController.text
                          .split(RegExp(r'[,\n]+'))
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      final stock = int.tryParse(stockController.text.trim()) ?? rawCodes.length;
                      final cost = int.tryParse(costController.text.trim()) ?? 0;
                      final code = rawCodes.isNotEmpty ? rawCodes.first : '';

                      try {
                        await firestoreService.addCoupon(
                          title: titleController.text.trim(),
                          description: descController.text.trim(),
                          cost: cost,
                          code: code,
                          stock: stock,
                          codes: rawCodes,
                        );
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx, true);
                        }
                      } catch (e) {
                        if (dialogCtx.mounted) {
                          setDialogState(() => isSubmitting = false);
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(
                              content: Text('Failed to add coupon: $e'),
                              backgroundColor: AppColors.errorText,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Add Coupon'),
            ),
          ],
        ),
      ),
    );

    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coupon successfully added to reward shop'),
          backgroundColor: AppColors.primaryDark,
        ),
      );
    }
  }

  Future<void> _confirmDeleteCoupon(BuildContext context, CouponModel coupon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Coupon?'),
        content: Text(
          'Are you sure you want to permanently delete "${coupon.title}"? Users will no longer be able to redeem it.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorText,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await firestoreService.removeCoupon(coupon.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${coupon.title}"'),
              backgroundColor: AppColors.primaryDark,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete coupon: $e'),
              backgroundColor: AppColors.errorText,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Action Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reward Inventory',
                style: AppTypography.heading.copyWith(fontSize: 16),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddCouponDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Coupon'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ),

        // Coupon List
        Expanded(
          child: StreamBuilder<List<CouponModel>>(
            stream: firestoreService.watchAvailableCoupons(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error loading coupons: ${snapshot.error}',
                      style: AppTypography.body.copyWith(color: AppColors.errorText),
                    ),
                  ),
                );
              }

              final coupons = snapshot.data ?? [];
              if (coupons.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.card_giftcard_outlined,
                          size: 48,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No coupons in the store yet.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _showAddCouponDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add First Coupon'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: coupons.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final coupon = coupons[index];
                  final isOutOfStock = coupon.stock <= 0;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOutOfStock ? AppColors.errorBg : AppColors.border,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Coupon Icon Container
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isOutOfStock
                                ? AppColors.errorBg
                                : AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.confirmation_number_outlined,
                            color: isOutOfStock
                                ? AppColors.errorText
                                : AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                coupon.title,
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (coupon.description.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  coupon.description,
                                  style: AppTypography.caption,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  // Cost pill
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${coupon.cost} pts',
                                      style: AppTypography.caption.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFFE65100),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  // Stock pill
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isOutOfStock
                                          ? AppColors.errorBg
                                          : AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isOutOfStock
                                          ? 'Out of stock'
                                          : '${coupon.stock} in stock',
                                      style: AppTypography.caption.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isOutOfStock
                                            ? AppColors.errorText
                                            : AppColors.primaryDark,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  // Code preview
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0F4F8),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      coupon.codes.length > 1
                                          ? '${coupon.codes.length} codes pool'
                                          : 'Code: ${coupon.code}',
                                      style: AppTypography.caption.copyWith(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: const Color(0xFF37474F),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Delete Action
                        IconButton(
                          tooltip: 'Delete Coupon',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.errorText,
                          ),
                          onPressed: () => _confirmDeleteCoupon(context, coupon),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
