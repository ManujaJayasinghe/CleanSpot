import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/theme_proposal.dart';
import 'current_user.dart';
import 'widgets/widgets.dart';

/// CleanSpot Profile screen displaying active user stats, menu options,
/// and authentication actions.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _showSignOutDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final textTheme = Theme.of(ctx).textTheme;

        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          title: Text(
            'Sign Out',
            style: (textTheme.titleLarge ?? AppTypography.heading).copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out?',
            style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: (textTheme.labelLarge ?? AppTypography.body).copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                // The router redirects to /login once the user is signed out.
                await FirebaseAuth.instance.signOut();
                try {
                  await GoogleSignIn.instance.signOut();
                } catch (_) {
                  // Not signed in with Google; nothing to clear.
                }
              },
              child: Text(
                'Sign out',
                style: (textTheme.labelLarge ?? AppTypography.body).copyWith(
                  color: AppColors.errorText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = CurrentUser.fromAuth();
    final initials = user.initials;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Title
              Text(
                'Profile',
                style: (textTheme.headlineMedium ?? AppTypography.title).copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // Centered Avatar & Info
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage: user.photoUrl != null &&
                              user.photoUrl!.isNotEmpty
                          ? NetworkImage(user.photoUrl!)
                          : null,
                      child: user.photoUrl == null ||
                              user.photoUrl!.isEmpty
                          ? Text(
                              initials,
                              style: (textTheme.titleLarge ?? AppTypography.heading).copyWith(
                                color: AppColors.primaryDark,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.name,
                      style: (textTheme.titleLarge ?? AppTypography.heading).copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email,
                      style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Points Card
              UserPoints(
                builder: (context, points) => PointsCard(
                  label: 'YOUR POINTS',
                  points: points,
                  caption: 'Earn more by reporting breeding sites.',
                ),
              ),
              const SizedBox(height: 20),

              // Navigation Tiles
              MenuTile(
                icon: Icons.assignment_outlined,
                title: 'My Reports',
                subtitle: 'Track your submitted reports',
                onTap: () => context.push('/profile/reports'),
              ),
              const SizedBox(height: 12),
              MenuTile(
                icon: Icons.confirmation_number_outlined,
                title: 'My Coupons',
                subtitle: 'View your redeemed rewards',
                onTap: () => context.push('/profile/coupons'),
              ),
              const SizedBox(height: 12),
              MenuTile(
                icon: Icons.analytics_outlined,
                title: 'Dengue Analysis',
                subtitle: 'Weekly trends & district statistics',
                onTap: () => context.push('/analysis'),
              ),
              const SizedBox(height: 12),
              MenuTile(
                icon: Icons.health_and_safety_outlined,
                title: 'Symptom Checker',
                subtitle: 'Clinical guide & risk self-check',
                onTap: () => context.push('/symptoms'),
              ),
              const SizedBox(height: 28),

              // Sign Out Button
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => _showSignOutDialog(context),
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Sign Out'),
                ),
              ),
              const SizedBox(height: 12),

              // Demo User Note
              Center(
                child: Text(
                  'Fictional demonstration user',
                  style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
