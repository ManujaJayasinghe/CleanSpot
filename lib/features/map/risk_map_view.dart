import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import 'map_filters.dart';
import 'map_projection.dart';

/// The live risk map: real OpenStreetMap street tiles with a heatmap or marker
/// overlay of valid reports, on an interactive Web Mercator viewport. Works
/// without a billed Google Cloud Maps SDK key. Automatically centres on the
/// newest report.
///
/// Used by the Map tab (`MapScreen`, interactive) and by the Home preview
/// (`RiskMapPreview`, non-interactive), so the two always show the same map.
/// Fills the space it is given.
class RiskMapView extends StatefulWidget {
  const RiskMapView({
    super.key,
    required this.reports,
    this.viewMode = MapViewMode.heatmap,
    this.timeRange = MapTimeRange.last7Days,
    this.interactive = true,
    this.onReportTap,
  });

  /// Live valid reports (`FirestoreService.watchValidReports`).
  final Stream<List<ReportModel>> reports;

  final MapViewMode viewMode;
  final MapTimeRange timeRange;

  /// When false the map only displays: no pan, zoom, pin taps or control
  /// buttons, so it can sit inside a scrolling page without fighting it.
  final bool interactive;

  /// Called when a pin or hotspot is tapped (interactive maps only).
  final void Function(ReportModel report)? onReportTap;

  @override
  State<RiskMapView> createState() => _RiskMapViewState();
}

class _RiskMapViewState extends State<RiskMapView> {
  /// Default center (Colombo) before any approved reports are loaded.
  static const double _defaultLat = 6.9271;
  static const double _defaultLng = 79.8612;
  static const double _defaultZoom = 13.0;
  static const double _focusedZoom = 15.0;

  double _centerLat = _defaultLat;
  double _centerLng = _defaultLng;
  double _zoom = _defaultZoom;
  double _baseScaleZoom = _defaultZoom;
  Offset? _lastFocalPoint;

  /// ID of the newest report we already auto-centered on, so a newly approved
  /// standing-water report automatically moves the map to its location once.
  String? _autoCenteredReportId;

  void _centerOnReport(ReportModel report, {double zoom = _focusedZoom}) {
    setState(() {
      _centerLat = report.location.latitude;
      _centerLng = report.location.longitude;
      _zoom = zoom;
    });
  }

  void _maybeAutoCenter(List<ReportModel> reports) {
    if (reports.isEmpty) return;
    // Sort newest first so we focus on the most recently approved report.
    final sorted = [...reports]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final newest = sorted.first;
    if (_autoCenteredReportId == newest.id) return;
    _autoCenteredReportId = newest.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerOnReport(newest);
    });
  }

  Widget _buildLegend() {
    Widget item(String label, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppTypography.caption),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Risk',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          item('Low', AppColors.primary),
          const SizedBox(width: 10),
          item('Medium', AppColors.warningText),
          const SizedBox(width: 10),
          item('High', AppColors.errorText),
        ],
      ),
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveMap(List<ReportModel> reports) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final centerWorld = project(_centerLat, _centerLng, _zoom);

        // Visible OpenStreetMap tiles for this viewport.
        final tiles = buildOsmTiles(
          centerWorld: centerWorld,
          zoom: _zoom,
          width: width,
          height: height,
        );

        // Project each valid report to screen coordinates.
        final projectedReports =
            <({ReportModel report, Offset pos, int nearby})>[];
        for (final r in reports) {
          final world = project(
            r.location.latitude,
            r.location.longitude,
            _zoom,
          );
          final pos = Offset(
            world.dx - centerWorld.dx + width / 2,
            world.dy - centerWorld.dy + height / 2,
          );
          projectedReports.add((report: r, pos: pos, nearby: 1));
        }

        // Count nearby reports within 60 px so clusters glow warmer (orange/red).
        final reportNodes = <({ReportModel report, Offset pos, int nearby})>[
          for (final item in projectedReports)
            (
              report: item.report,
              pos: item.pos,
              nearby: projectedReports
                  .where((other) => (other.pos - item.pos).distance <= 60)
                  .length,
            ),
        ];

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            _baseScaleZoom = _zoom;
            _lastFocalPoint = details.localFocalPoint;
          },
          onScaleUpdate: (details) {
            final prevFocal = _lastFocalPoint ?? details.localFocalPoint;
            final delta = details.localFocalPoint - prevFocal;
            _lastFocalPoint = details.localFocalPoint;

            setState(() {
              if ((details.scale - 1.0).abs() > 0.01) {
                _zoom = (_baseScaleZoom + math.log(details.scale) / math.ln2)
                    .clamp(6.0, 18.0);
              }
              final currentWorld = project(_centerLat, _centerLng, _zoom);
              final shifted = Offset(
                currentWorld.dx - delta.dx,
                currentWorld.dy - delta.dy,
              );
              final (newLat, newLng) = unproject(shifted, _zoom);
              _centerLat = newLat;
              _centerLng = newLng;
            });
          },
          child: ClipRect(
            child: Stack(
              children: [
                // 1. Clean cartographic fallback grid while tiles stream in
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BaseGridPainter(centerWorld: centerWorld),
                  ),
                ),

                // 2. Real OpenStreetMap street tiles
                ...tiles,

                // 3. Heatmap layer (when Heatmap mode is active)
                if (widget.viewMode == MapViewMode.heatmap &&
                    reportNodes.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _HeatmapOverlayPainter(
                          points: [
                            for (final n in reportNodes)
                              (pos: n.pos, density: n.nearby),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 4. Interactive tap targets / pins for reports
                for (final node in reportNodes)
                  if (node.pos.dx >= -48 &&
                      node.pos.dx <= width + 48 &&
                      node.pos.dy >= -48 &&
                      node.pos.dy <= height + 48)
                    Positioned(
                      left:
                          node.pos.dx -
                          (widget.viewMode == MapViewMode.markers ? 20 : 18),
                      top:
                          node.pos.dy -
                          (widget.viewMode == MapViewMode.markers ? 36 : 18),
                      child: GestureDetector(
                        onTap: () => widget.onReportTap?.call(node.report),
                        child: widget.viewMode == MapViewMode.markers
                            ? _buildMarkerPin(node.nearby)
                            : _buildHeatmapHotspotDot(node.nearby),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarkerPin(int nearbyCount) {
    final pinColor = nearbyCount >= 4
        ? AppColors.errorText
        : (nearbyCount >= 2 ? AppColors.warningText : AppColors.primaryDark);

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: pinColor,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: pinColor.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.water_drop,
              color: AppColors.surface,
              size: 17,
            ),
          ),
        ],
      ),
    );
  }

  /// Subtle tappable center point inside each heatmap zone so the user can
  /// also tap a heatmap spot to inspect the approved standing-water report.
  Widget _buildHeatmapHotspotDot(int nearbyCount) {
    final dotColor = nearbyCount >= 4
        ? AppColors.errorText
        : (nearbyCount >= 2 ? AppColors.warningText : AppColors.primaryDark);

    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      color: Colors.transparent,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 2),
          boxShadow: [
            BoxShadow(color: dotColor.withValues(alpha: 0.4), blurRadius: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ReportModel>>(
      stream: widget.reports,
      builder: (context, snapshot) {
        final allValid = snapshot.data ?? const [];
        final filtered = filterReports(
          allValid,
          widget.timeRange,
          DateTime.now(),
        );

        if (filtered.isNotEmpty) {
          _maybeAutoCenter(filtered);
        }

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !widget.interactive,
                child: _buildInteractiveMap(filtered),
              ),
            ),
            Positioned(left: 12, bottom: 12, child: _buildLegend()),
            if (widget.interactive)
              Positioned(
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (filtered.isNotEmpty) ...[
                      _buildMapControlButton(
                        icon: Icons.my_location,
                        tooltip: 'Center on latest approved report',
                        onTap: () {
                          final sorted = [
                            ...filtered,
                          ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                          _centerOnReport(sorted.first);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildMapControlButton(
                      icon: Icons.add,
                      tooltip: 'Zoom in',
                      onTap: () =>
                          setState(() => _zoom = (_zoom + 1).clamp(6.0, 18.0)),
                    ),
                    const SizedBox(height: 8),
                    _buildMapControlButton(
                      icon: Icons.remove,
                      tooltip: 'Zoom out',
                      onTap: () =>
                          setState(() => _zoom = (_zoom - 1).clamp(6.0, 18.0)),
                    ),
                  ],
                ),
              ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (snapshot.hasError)
              const _MapMessage(
                icon: Icons.cloud_off_outlined,
                text: 'Could not load reports. Check your connection.',
              )
            else if (filtered.isEmpty)
              const _MapMessage(
                icon: Icons.search_off,
                text: 'No valid reports in this period.',
              ),
          ],
        );
      },
    );
  }
}

/// Subtle background grid drawn behind street tiles while loading or offline.
class _BaseGridPainter extends CustomPainter {
  const _BaseGridPainter({required this.centerWorld});

  final Offset centerWorld;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEDF3ED),
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFDCE5DC)
      ..strokeWidth = 1;

    const step = 64.0;
    final startX = -(centerWorld.dx % step);
    final startY = -(centerWorld.dy % step);

    for (var x = startX; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = startY; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_BaseGridPainter oldDelegate) =>
      oldDelegate.centerWorld != centerWorld;
}

/// Renders radial risk heatmap blobs (Low -> Medium -> High) around each
/// valid report's projected screen position.
class _HeatmapOverlayPainter extends CustomPainter {
  const _HeatmapOverlayPainter({required this.points});

  final List<({Offset pos, int density})> points;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in points) {
      final radius = (55.0 + (p.density - 1) * 10.0).clamp(55.0, 95.0);
      final innerColor = p.density >= 3
          ? AppColors.errorText.withValues(alpha: 0.60)
          : (p.density == 2
                ? AppColors.warningText.withValues(alpha: 0.55)
                : AppColors.errorText.withValues(alpha: 0.45));
      final midColor = p.density >= 2
          ? AppColors.warningText.withValues(alpha: 0.38)
          : AppColors.warningText.withValues(alpha: 0.30);
      final outerColor = AppColors.primary.withValues(alpha: 0.22);

      final shader = RadialGradient(
        colors: [
          innerColor,
          midColor,
          outerColor,
          AppColors.primary.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.38, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: p.pos, radius: radius));

      canvas.drawCircle(p.pos, radius, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_HeatmapOverlayPainter oldDelegate) =>
      oldDelegate.points != points;
}

/// Small notice card centred on the map (empty / error states).
class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: AppTypography.body)),
          ],
        ),
      ),
    );
  }
}
