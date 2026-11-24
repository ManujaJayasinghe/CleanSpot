import 'package:flutter/material.dart';

import '../../../app/theme_proposal.dart';
import '../../../models/report_model.dart';
import '../../../models/user_model.dart';
import '../../../services/firestore_service.dart';

/// Top stats component displaying key platform metrics:
/// Total users, total reports, valid reports, cleared reports, and rejected reports.
class AdminStatsCards extends StatelessWidget {
  final FirestoreService firestoreService;

  const AdminStatsCards({
    super.key,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: firestoreService.watchAllUsers(),
      builder: (context, userSnap) {
        final totalUsers = userSnap.data?.length;

        return StreamBuilder<List<ReportModel>>(
          stream: firestoreService.watchAllReports(),
          builder: (context, reportSnap) {
            final reports = reportSnap.data ?? [];
            final totalReports = reportSnap.hasData ? reports.length : null;

            int validCount = 0;
            int clearedCount = 0;
            int rejectedCount = 0;

            if (reportSnap.hasData) {
              for (final r in reports) {
                switch (r.status.toLowerCase()) {
                  case 'valid':
                    validCount++;
                    break;
                  case 'cleared':
                    clearedCount++;
                    break;
                  case 'rejected':
                    rejectedCount++;
                    break;
                }
              }
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Platform Overview',
                    style: AppTypography.heading.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Total Users',
                          value: totalUsers != null ? '$totalUsers' : '...',
                          icon: Icons.people_alt_outlined,
                          color: AppColors.primary,
                          bgColor: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          title: 'Total Reports',
                          value: totalReports != null ? '$totalReports' : '...',
                          icon: Icons.assignment_outlined,
                          color: const Color(0xFF2E7D32),
                          bgColor: const Color(0xFFE8F5E9),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Valid',
                          value: reportSnap.hasData ? '$validCount' : '...',
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF2E7D32),
                          bgColor: const Color(0xFFE8F5E9),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          title: 'Cleared',
                          value: reportSnap.hasData ? '$clearedCount' : '...',
                          icon: Icons.cleaning_services_outlined,
                          color: const Color(0xFF1976D2),
                          bgColor: const Color(0xFFE3F2FD),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          title: 'Rejected',
                          value: reportSnap.hasData ? '$rejectedCount' : '...',
                          icon: Icons.cancel_outlined,
                          color: AppColors.errorText,
                          bgColor: AppColors.errorBg,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.title.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
