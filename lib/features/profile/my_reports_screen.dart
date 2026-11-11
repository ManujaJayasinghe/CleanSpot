import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';
import 'widgets/widgets.dart';

/// Screen displaying submitted dengue breeding site reports with filter options.
/// Streams live reports from Firestore where uid == currentUser.uid.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  String _selectedFilter = 'all'; // 'all' | 'pending' | 'reviewed'

  List<ReportModel> _filterReports(List<ReportModel> all) {
    if (_selectedFilter == 'pending') {
      return all.where((r) => r.status.toLowerCase() == 'pending').toList();
    }
    if (_selectedFilter == 'reviewed') {
      return all.where((r) => r.status.toLowerCase() != 'pending').toList();
    }
    return all;
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'pm' : 'am';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour:$minute $ampm';
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;

    return InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, ReportModel report) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  report.type,
                  style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip.fromStatus(
                text: report.status,
                status: report.status,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${report.lat.toStringAsFixed(4)}° N, ${report.lng.toStringAsFixed(4)}° E',
            style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          if (report.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              report.description,
              style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (report.aiReason != null && report.aiReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'AI feedback: ${report.aiReason!}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.error,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            _formatDate(report.createdAt),
            style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryLight,
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: AppColors.primaryDark,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No reports found',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No reports match your current filter.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar with back arrow
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border, width: 1),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'My Reports',
                    style: (textTheme.headlineSmall ?? AppTypography.title).copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Subtitle
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Small actions, recorded with care.',
                  style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All reports', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Pending', 'pending'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Reviewed', 'reviewed'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Stream reports from Firestore
              StreamBuilder<List<ReportModel>>(
                stream: uid.isNotEmpty
                    ? _firestoreService.watchUserReports(uid)
                    : Stream.value([]),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final allReports = snapshot.data ?? [];
                  final filtered = _filterReports(allReports);

                  if (filtered.isEmpty) {
                    return _buildEmptyState(context);
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildReportCard(context, filtered[index]);
                    },
                  );
                },
              ),
              const SizedBox(height: 24),

              // Mint TipBanner at the bottom
              const TipBanner(
                text:
                    'Reports are reviewed automatically by AI before appearing as valid markers on the map.',
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
