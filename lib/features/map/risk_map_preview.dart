import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';
import 'risk_map_view.dart';

/// A fixed-height card on the Home page showing the same live risk map as the
/// Map tab ([RiskMapView], heatmap, last 7 days).
///
/// The preview is not interactive: it never pans or zooms, so it cannot fight
/// the page scroll. Tapping anywhere on the card, or its "Open full map" chip,
/// opens the full Map tab (`/map`, the same call the bottom navigation uses).
class RiskMapPreview extends StatefulWidget {
  const RiskMapPreview({super.key, this.reports, this.height = 300});

  /// Report stream override, for tests. Defaults to the live valid reports.
  final Stream<List<ReportModel>>? reports;

  final double height;

  @override
  State<RiskMapPreview> createState() => _RiskMapPreviewState();
}

class _RiskMapPreviewState extends State<RiskMapPreview> {
  late final Stream<List<ReportModel>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = widget.reports ?? FirestoreService().watchValidReports();
  }

  void _openFullMap() => context.go('/map');

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Risk map preview. Open full map',
      child: Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: RiskMapView(reports: _reports, interactive: false),
            ),
            // One tap target over the whole preview.
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('risk-map-preview-tap'),
                  onTap: _openFullMap,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Open full map',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
