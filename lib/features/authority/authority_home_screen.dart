import 'package:flutter/material.dart';

import '../../app/session.dart';
import '../../app/theme_proposal.dart';

/// Placeholder for the authority dashboard (valid reports to mark as cleared).
/// Reached only by authorities and admins: the route guard in
/// `lib/app/session.dart` sends everyone else away. Teammates build the real
/// screen here.
class AuthorityHomeScreen extends StatelessWidget {
  const AuthorityHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Authority'),
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
            'Authority dashboard\n\nComing soon.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
