import 'package:flutter/material.dart';

import '../../app/session.dart';
import '../../app/theme_proposal.dart';

/// Placeholder for the admin dashboard (users, roles, blocking, coupons).
/// Reached only by admins: the route guard in `lib/app/session.dart` sends
/// everyone else away. Teammates build the real screen here.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: signOutEverywhere,
          ),
        ],
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Admin dashboard\n\nComing soon.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
