import 'package:flutter/material.dart';

import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';
import '../ai_validation/validation_result.dart';
import '../report/report_photo_view.dart';
import 'map_filters.dart';
import 'risk_map_view.dart';

/// Risk map tab: the live [RiskMapView] with the heatmap/marker toggle, the
/// time-range chips, and a bottom sheet for a tapped report.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final FirestoreService _service;
  late final Stream<List<ReportModel>> _reports;

  MapViewMode _viewMode = MapViewMode.heatmap;
  MapTimeRange _timeRange = MapTimeRange.last7Days;

  @override
  void initState() {
    super.initState();
    _service = FirestoreService();
    _reports = _service.watchValidReports();
  }

  void _showReportSheet(ReportModel report) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ReportSheet(report: report, service: _service),
    );
  }

  Widget _buildToggle() {
    Widget segment(String label, MapViewMode mode) {
      final selected = _viewMode == mode;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _viewMode = mode),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected
                    ? AppColors.primaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          segment('Heatmap', MapViewMode.heatmap),
          segment('Markers', MapViewMode.markers),
        ],
      ),
    );
  }

  Widget _buildTimeChip(MapTimeRange range) {
    final selected = _timeRange == range;
    return InkWell(
      onTap: () => setState(() => _timeRange = range),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          range.label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.primaryDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Risk Map',
                    style: (textTheme.headlineMedium ?? AppTypography.title)
                        .copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Live valid reports. Redder means more reports nearby.',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: 14),
                  _buildToggle(),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final range in MapTimeRange.values) ...[
                          _buildTimeChip(range),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: RiskMapView(
                reports: _reports,
                viewMode: _viewMode,
                timeRange: _timeRange,
                onReportTap: _showReportSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet shown when a marker or hotspot is tapped: photo, type,
/// coordinates, AI verification reason, and date.
class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.report, required this.service});

  final ReportModel report;
  final FirestoreService service;

  @override
  Widget build(BuildContext context) {
    final photoId = report.photoId.isNotEmpty ? report.photoId : report.id;
    final latText = report.location.latitude.toStringAsFixed(5);
    final lngText = report.location.longitude.toStringAsFixed(5);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ReportPhotoView(
                reportId: photoId,
                width: double.infinity,
                height: 200,
                loader: service.getReportPhoto,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              SiteCategory.labelFor(report.type),
              style: AppTypography.heading,
            ),
            const SizedBox(height: 4),
            Text(
              'Reported ${formatReportDate(report.createdAt)} · $latText° N, $lngText° E',
              style: AppTypography.caption,
            ),
            if (report.aiReason != null && report.aiReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(report.aiReason!, style: AppTypography.body),
            ] else if (report.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(report.description, style: AppTypography.body),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: AppBadges.successDecoration,
              child: const Text(
                'Valid report',
                style: AppBadges.successTextStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
