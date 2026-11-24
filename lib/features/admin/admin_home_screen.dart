import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme_proposal.dart';
import '../../services/firestore_service.dart';
import 'widgets/admin_coupons_tab.dart';
import 'widgets/admin_stats_cards.dart';
import 'widgets/admin_users_tab.dart';

/// Admin dashboard screen providing platform-level controls:
/// - Real-time statistics (total users, total reports, valid/rejected/cleared breakdown)
/// - User search, role modification (user/authority/admin), and user blocking/unblocking
/// - Reward coupon inventory management (adding with stock pools & removing coupons)
class AdminHomeScreen extends StatefulWidget {
  final FirestoreService? firestoreService;

  const AdminHomeScreen({
    super.key,
    this.firestoreService,
  });

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with SingleTickerProviderStateMixin {
  late final FirestoreService _firestoreService;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out from the Admin Dashboard?'),
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
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await signOutEverywhere();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                color: Color(0xFF7B1FA2),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Admin Dashboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'View User App',
            icon: const Icon(Icons.explore_outlined),
            onPressed: () => context.push('/home'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSignOut(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Overview Stats
            AdminStatsCards(firestoreService: _firestoreService),

            const SizedBox(height: 4),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: AppColors.primaryDark,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.people_outline, size: 20),
                    text: 'Users & Roles',
                  ),
                  Tab(
                    icon: Icon(Icons.card_giftcard_outlined, size: 20),
                    text: 'Coupons & Stock',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  AdminUsersTab(firestoreService: _firestoreService),
                  AdminCouponsTab(firestoreService: _firestoreService),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
