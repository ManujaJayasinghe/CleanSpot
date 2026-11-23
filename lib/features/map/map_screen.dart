import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';
import '../ai_validation/validation_result.dart';
import '../report/report_photo_view.dart';
import 'map_filters.dart';

/// Risk map: a live heatmap (or markers) of valid reports around the user.
///
/// Renders real OpenStreetMap street tiles with an interactive Web Mercator
/// viewport and a heatmap/marker overlay so the map works immediately without
/// requiring a billed Google Cloud Maps SDK key. Automatically centers on the
/// newest approved report's GPS coordinates.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// Default center (Colombo) before any approved reports are loaded.
  static const double _defaultLat = 6.9271;
  static const double _defaultLng = 79.8612;
  static const double _defaultZoom = 13.0;
  static const double _focusedZoom = 15.0;

  late final FirestoreService _service;
  late final Stream<List<ReportModel>> _reports;

  MapViewMode _viewMode = MapViewMode.heatmap;
  MapTimeRange _timeRange = MapTimeRange.last7Days;

  double _centerLat = _defaultLat;
  double _centerLng = _defaultLng;
  double _zoom = _defaultZoom;
  double _baseScaleZoom = _defaultZoom;
  Offset? _lastFocalPoint;

  /// ID of the newest report we already auto-centered on, so a newly approved
  /// standing-water report automatically moves the map to its location once.
  String? _autoCenteredReportId;

  @override
  void initState() {
    super.initState();
    _service = FirestoreService();
    _reports = _service.watchValidReports();
  }

  // ---------------------------------------------------------------------------
  // Web Mercator projection helpers
  // ---------------------------------------------------------------------------

  static double _worldSize(double zoom) => 256.0 * math.pow(2.0, zoom);

  static Offset _project(double lat, double lng, double zoom) {
    final size = _worldSize(zoom);
    final x = (lng + 180.0) / 360.0 * size;
    final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    final y =
        (0.5 - math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi)) *
        size;
    return Offset(x, y);
  }

  static (double lat, double lng) _unproject(Offset world, double zoom) {
    final size = _worldSize(zoom);
    final lng = ((world.dx / size) * 360.0 - 180.0).clamp(-180.0, 180.0);
    final n = math.pi - 2.0 * math.pi * (world.dy / size);
    final lat =
        ((180.0 / math.pi) * math.atan(0.5 * (math.exp(n) - math.exp(-n))))
            .clamp(-85.0, 85.0);
    return (lat, lng);
  }

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
        final centerWorld = _project(_centerLat, _centerLng, _zoom);

        // Compute integer tile zoom and visible OpenStreetMap tiles.
        final tileZ = _zoom.round().clamp(3, 18);
        final tileScale = math.pow(2.0, _zoom - tileZ).toDouble();
        final tileScreenSize = 256.0 * tileScale;
        final maxTileIndex = (1 << tileZ) - 1;

        final minTx =
            ((centerWorld.dx - width / 2) / tileScreenSize).floor();
        final maxTx =
            ((centerWorld.dx + width / 2) / tileScreenSize).floor();
        final minTy =
            ((centerWorld.dy - height / 2) / tileScreenSize).floor();
        final maxTy =
            ((centerWorld.dy + height / 2) / tileScreenSize).floor();

        final tiles = <Widget>[];
        for (var ty = minTy; ty <= maxTy; ty++) {
          if (ty < 0 || ty > maxTileIndex) continue;
          for (var tx = minTx; tx <= maxTx; tx++) {
            final wrappedTx =
                ((tx % (maxTileIndex + 1)) + (maxTileIndex + 1)) %
                (maxTileIndex + 1);
            final left = tx * tileScreenSize - centerWorld.dx + width / 2;
            final top = ty * tileScreenSize - centerWorld.dy + height / 2;
            tiles.add(
              Positioned(
                key: ValueKey('tile-$tileZ-$wrappedTx-$ty'),
                left: left,
                top: top,
                width: tileScreenSize + 0.5,
                height: tileScreenSize + 0.5,
                child: Image.network(
                  'https://tile.openstreetmap.org/$tileZ/$wrappedTx/$ty.png',
                  headers: const {'User-Agent': 'CleanSpot/1.0 (MAD Project)'},
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            );
          }
        }

        // Project each valid report to screen coordinates.
        final projectedReports = <({ReportModel report, Offset pos, int nearby})>[];
        for (final r in reports) {
          final world = _project(
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
              final currentWorld = _project(_centerLat, _centerLng, _zoom);
              final shifted = Offset(
                currentWorld.dx - delta.dx,
                currentWorld.dy - delta.dy,
              );
              final (newLat, newLng) = _unproject(shifted, _zoom);
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
                if (_viewMode == MapViewMode.heatmap && reportNodes.isNotEmpty)
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
                      left: node.pos.dx - (_viewMode == MapViewMode.markers ? 20 : 18),
                      top: node.pos.dy - (_viewMode == MapViewMode.markers ? 36 : 18),
                      child: GestureDetector(
                        onTap: () => _showReportSheet(node.report),
                        child: _viewMode == MapViewMode.markers
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
            BoxShadow(
              color: dotColor.withValues(alpha: 0.4),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapArea() {
    return StreamBuilder<List<ReportModel>>(
      stream: _reports,
      builder: (context, snapshot) {
        final allValid = snapshot.data ?? const [];
        final filtered = filterReports(
          allValid,
          _timeRange,
          DateTime.now(),
        );

        if (filtered.isNotEmpty) {
          _maybeAutoCenter(filtered);
        }

        return Stack(
          children: [
            Positioned.fill(
              child: _buildInteractiveMap(filtered),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _buildLegend(),
            ),
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
                        final sorted = [...filtered]
                          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
            Expanded(child: _buildMapArea()),
          ],
        ),
      ),
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
