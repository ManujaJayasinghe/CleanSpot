import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/session.dart';
import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';
import '../../services/report_write_plan.dart';
import '../ai_validation/validation_result.dart';
import '../analysis/risk_index.dart';
import '../map/map_filters.dart';
import '../report/report_photo_view.dart';

/// Determines the district/area name for a [report] from its GPS coordinates.
/// Reports without valid coordinates `(0, 0)` are grouped under `'Unknown area'`.
String areaForReport(ReportModel report) {
  final lat = report.location.latitude != 0
      ? report.location.latitude
      : report.lat;
  final lng = report.location.longitude != 0
      ? report.location.longitude
      : report.lng;
  if (lat == 0 && lng == 0) return 'Unknown area';
  return nearestDistrict(lat, lng);
}

/// Returns valid [reports] sorted by area name (A–Z, with `'Unknown area'` last),
/// then by highest "still present" [ReportModel.confirmationCount], then newest
/// [ReportModel.createdAt] first.
List<ReportModel> sortReportsByArea(Iterable<ReportModel> reports) {
  final list = reports.toList();
  list.sort((a, b) {
    final areaA = areaForReport(a);
    final areaB = areaForReport(b);
    if (areaA != areaB) {
      if (areaA == 'Unknown area') return 1;
      if (areaB == 'Unknown area') return -1;
      return areaA.compareTo(areaB);
    }
    final byConfirmations = b.confirmationCount.compareTo(a.confirmationCount);
    if (byConfirmations != 0) return byConfirmations;
    final byDate = b.createdAt.compareTo(a.createdAt);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  });
  return list;
}

/// Groups [reports] by area in sorted area order.
Map<String, List<ReportModel>> groupReportsByArea(
  Iterable<ReportModel> reports,
) {
  final sorted = sortReportsByArea(reports);
  final grouped = <String, List<ReportModel>>{};
  for (final r in sorted) {
    final area = areaForReport(r);
    (grouped[area] ??= <ReportModel>[]).add(r);
  }
  return grouped;
}

/// Human-readable label for how many times a report was marked "still present".
String stillPresentLabel(int count) =>
    'Marked "still present": $count ${count == 1 ? 'time' : 'times'}';

/// Authority dashboard screen for inspecting valid breeding-site reports by
/// area on a live risk heatmap and marking sites as cleared.
class AuthorityHomeScreen extends StatefulWidget {
  const AuthorityHomeScreen({
    super.key,
    this.firestoreService,
    this.validReportsStream,
    this.allReportsStream,
    this.onMarkCleared,
    this.photoLoader,
    this.onSignOut,
  });

  final FirestoreService? firestoreService;
  final Stream<List<ReportModel>>? validReportsStream;
  final Stream<List<ReportModel>>? allReportsStream;
  final Future<void> Function(String reportId)? onMarkCleared;
  final Future<Uint8List?> Function(String reportId)? photoLoader;
  final Future<void> Function()? onSignOut;

  @override
  State<AuthorityHomeScreen> createState() => _AuthorityHomeScreenState();
}

class _AuthorityHomeScreenState extends State<AuthorityHomeScreen> {
  static const double _defaultLat = 6.9271;
  static const double _defaultLng = 79.8612;
  static const double _defaultZoom = 11.5;
  static const double _focusedZoom = 15.0;

  FirestoreService? _lazyService;
  FirestoreService get _service =>
      widget.firestoreService ?? (_lazyService ??= FirestoreService());

  late final Stream<List<ReportModel>> _validReportsStream;
  late final Stream<List<ReportModel>>? _allReportsStream;

  MapViewMode _viewMode = MapViewMode.heatmap;
  String? _selectedArea;

  double _centerLat = _defaultLat;
  double _centerLng = _defaultLng;
  double _zoom = _defaultZoom;
  double _baseScaleZoom = _defaultZoom;
  Offset? _lastFocalPoint;
  String? _autoCenteredReportId;

  /// IDs of reports marked as cleared during this session so the heatmap cools
  /// down and the cleared count increments immediately upon completion.
  final Set<String> _clearedInSessionIds = <String>{};

  /// IDs currently being marked as cleared (prevents duplicate submissions).
  final Set<String> _clearingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _validReportsStream =
        widget.validReportsStream ?? _service.watchValidReports();
    if (widget.allReportsStream != null) {
      _allReportsStream = widget.allReportsStream;
    } else if (widget.validReportsStream == null ||
        widget.firestoreService != null) {
      _allReportsStream = _service.watchAllReports();
    } else {
      _allReportsStream = null;
    }
  }

  Future<Uint8List?> _loadPhoto(String reportId) =>
      (widget.photoLoader ?? _service.getReportPhoto)(reportId);

  Future<void> _handleMarkCleared(
    ReportModel report, {
    BuildContext? sheetContext,
  }) async {
    if (_clearingIds.contains(report.id)) return;
    setState(() => _clearingIds.add(report.id));

    try {
      final clearFn = widget.onMarkCleared ?? _service.markReportCleared;
      await clearFn(report.id);
      if (!mounted) return;
      if (sheetContext != null && sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
      setState(() {
        _clearingIds.remove(report.id);
        _clearedInSessionIds.add(report.id);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Cleared ${SiteCategory.labelFor(report.type)} in ${areaForReport(report)}. Heatmap updated.',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _clearingIds.remove(report.id));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not mark report as cleared. Please try again.',
            ),
          ),
        );
    }
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

  (double lat, double lng) _coordsOf(ReportModel report) {
    final lat = report.location.latitude != 0
        ? report.location.latitude
        : report.lat;
    final lng = report.location.longitude != 0
        ? report.location.longitude
        : report.lng;
    return (lat, lng);
  }

  void _centerOnReport(ReportModel report, {double zoom = _focusedZoom}) {
    final (lat, lng) = _coordsOf(report);
    if (lat == 0 && lng == 0) return;
    setState(() {
      _centerLat = lat;
      _centerLng = lng;
      _zoom = zoom;
    });
  }

  void _maybeAutoCenter(List<ReportModel> reports) {
    final mappable = reports.where(isMappable).toList();
    if (mappable.isEmpty) return;
    final sorted = [...mappable]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final newest = sorted.first;
    if (_autoCenteredReportId == newest.id) return;
    _autoCenteredReportId = newest.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerOnReport(newest, zoom: 13.5);
    });
  }

  void _showReportDetailSheet(ReportModel report) {
    _centerOnReport(report);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final isClearing = _clearingIds.contains(report.id);
          return _AuthorityReportDetailSheet(
            report: report,
            photoLoader: _loadPhoto,
            isClearing: isClearing,
            onMarkCleared: () async {
              setSheetState(() {});
              await _handleMarkCleared(report, sheetContext: sheetCtx);
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI Builders
  // ---------------------------------------------------------------------------

  Widget _buildStatsHeader({
    required int activeCount,
    required int clearedCount,
    required int areaCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: _SummaryStatCard(
            label: 'Active sites',
            value: '$activeCount',
            icon: Icons.warning_amber_rounded,
            color: AppColors.warningText,
            bgColor: AppColors.warningBg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryStatCard(
            key: const ValueKey('sites-cleared-card'),
            label: 'Sites cleared',
            value: '$clearedCount',
            icon: Icons.cleaning_services_outlined,
            color: AppColors.primaryDark,
            bgColor: AppColors.primaryLight,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryStatCard(
            label: 'Areas',
            value: '$areaCount',
            icon: Icons.place_outlined,
            color: const Color(0xFF1976D2),
            bgColor: const Color(0xFFE3F2FD),
          ),
        ),
      ],
    );
  }

  Widget _buildViewModeToggle() {
    Widget segment(String label, MapViewMode mode) {
      final selected = _viewMode == mode;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _viewMode = mode),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
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

  Widget _buildLegend() {
    Widget item(String label, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption.copyWith(fontSize: 11)),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Risk',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          item('Low', AppColors.primary),
          const SizedBox(width: 8),
          item('Medium', AppColors.warningText),
          const SizedBox(width: 8),
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
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard(List<ReportModel> mapReports) {
    final mappable = mapReports.where(isMappable).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.map_outlined,
                size: 18,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Live Risk Heatmap',
                  style: AppTypography.heading.copyWith(fontSize: 16),
                ),
              ),
              SizedBox(width: 170, child: _buildViewModeToggle()),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 230,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(child: _buildInteractiveMapCanvas(mappable)),
                  Positioned(left: 10, bottom: 10, child: _buildLegend()),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mappable.isNotEmpty) ...[
                          _buildMapControlButton(
                            icon: Icons.my_location,
                            tooltip: 'Center on latest report',
                            onTap: () {
                              final sorted = [...mappable]
                                ..sort(
                                  (a, b) => b.createdAt.compareTo(a.createdAt),
                                );
                              _centerOnReport(sorted.first);
                            },
                          ),
                          const SizedBox(height: 6),
                        ],
                        _buildMapControlButton(
                          icon: Icons.add,
                          tooltip: 'Zoom in',
                          onTap: () => setState(
                            () => _zoom = (_zoom + 1).clamp(6.0, 18.0),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildMapControlButton(
                          icon: Icons.remove,
                          tooltip: 'Zoom out',
                          onTap: () => setState(
                            () => _zoom = (_zoom - 1).clamp(6.0, 18.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (mappable.isEmpty)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Text(
                          'All breeding sites cleared — heatmap is cool.',
                          style: AppTypography.caption,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveMapCanvas(List<ReportModel> reports) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final centerWorld = _project(_centerLat, _centerLng, _zoom);

        final tileZ = _zoom.round().clamp(3, 18);
        final tileScale = math.pow(2.0, _zoom - tileZ).toDouble();
        final tileScreenSize = 256.0 * tileScale;
        final maxTileIndex = (1 << tileZ) - 1;

        final minTx = ((centerWorld.dx - width / 2) / tileScreenSize).floor();
        final maxTx = ((centerWorld.dx + width / 2) / tileScreenSize).floor();
        final minTy = ((centerWorld.dy - height / 2) / tileScreenSize).floor();
        final maxTy = ((centerWorld.dy + height / 2) / tileScreenSize).floor();

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
                key: ValueKey('auth-tile-$tileZ-$wrappedTx-$ty'),
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

        final projected = <({ReportModel report, Offset pos})>[];
        for (final r in reports) {
          final (lat, lng) = _coordsOf(r);
          final world = _project(lat, lng, _zoom);
          final pos = Offset(
            world.dx - centerWorld.dx + width / 2,
            world.dy - centerWorld.dy + height / 2,
          );
          projected.add((report: r, pos: pos));
        }

        final nodes = <({ReportModel report, Offset pos, int nearby})>[
          for (final item in projected)
            (
              report: item.report,
              pos: item.pos,
              nearby: projected
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
                Positioned.fill(
                  child: CustomPaint(
                    painter: _AuthorityGridPainter(centerWorld: centerWorld),
                  ),
                ),
                ...tiles,
                if (_viewMode == MapViewMode.heatmap && nodes.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _AuthorityHeatmapPainter(
                          points: [
                            for (final n in nodes)
                              (pos: n.pos, density: n.nearby),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (final node in nodes)
                  if (node.pos.dx >= -48 &&
                      node.pos.dx <= width + 48 &&
                      node.pos.dy >= -48 &&
                      node.pos.dy <= height + 48)
                    Positioned(
                      left: node.pos.dx - 18,
                      top: node.pos.dy - 18,
                      child: GestureDetector(
                        onTap: () => _showReportDetailSheet(node.report),
                        child: _viewMode == MapViewMode.markers
                            ? _buildMarkerPin(node.nearby)
                            : _buildHotspotDot(node.nearby),
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
    return Container(
      width: 36,
      height: 36,
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
      child: const Icon(Icons.water_drop, color: AppColors.surface, size: 17),
    );
  }

  Widget _buildHotspotDot(int nearbyCount) {
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
        ),
      ),
    );
  }

  Widget _buildAreaFilterChips(
    Map<String, List<ReportModel>> grouped,
    int totalCount,
  ) {
    if (grouped.isEmpty) return const SizedBox.shrink();

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            label: 'All areas ($totalCount)',
            selected: _selectedArea == null,
            onTap: () => setState(() => _selectedArea = null),
          ),
          for (final entry in grouped.entries) ...[
            const SizedBox(width: 8),
            chip(
              label: '${entry.key} (${entry.value.length})',
              selected: _selectedArea == entry.key,
              onTap: () {
                setState(() => _selectedArea = entry.key);
                if (entry.value.isNotEmpty) {
                  _centerOnReport(entry.value.first, zoom: 13.5);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAreaSection(String area, List<ReportModel> reports) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            children: [
              const Icon(
                Icons.location_city_outlined,
                size: 18,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 6),
              Text(area, style: AppTypography.heading.copyWith(fontSize: 16)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: AppBadges.successDecoration,
                child: Text(
                  '${reports.length} ${reports.length == 1 ? 'site' : 'sites'}',
                  style: AppBadges.successTextStyle.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        for (final report in reports) ...[
          _AuthorityReportCard(
            key: ValueKey('report-card-${report.id}'),
            report: report,
            area: area,
            photoLoader: _loadPhoto,
            isClearing: _clearingIds.contains(report.id),
            onTap: () => _showReportDetailSheet(report),
            onMarkCleared: () => _handleMarkCleared(report),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  int _computeClearedCount(List<ReportModel>? allReports) {
    final ids = <String>{..._clearedInSessionIds};
    if (allReports != null) {
      for (final r in allReports) {
        if (r.status.toLowerCase() == reportStatusCleared) {
          ids.add(r.id);
        }
      }
    }
    return ids.length;
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
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: AppColors.primaryDark,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Authority Dashboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => (widget.onSignOut ?? signOutEverywhere)(),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<ReportModel>>(
          stream: _allReportsStream,
          builder: (context, allSnap) {
            final clearedCount = _computeClearedCount(allSnap.data);

            return StreamBuilder<List<ReportModel>>(
              stream: _validReportsStream,
              builder: (context, validSnap) {
                final rawValid = validSnap.data ?? const <ReportModel>[];
                // Exclude reports cleared in this session immediately so the
                // heatmap cools down without waiting for a round-trip.
                final activeValid = rawValid
                    .where((r) => !_clearedInSessionIds.contains(r.id))
                    .toList();
                final grouped = groupReportsByArea(activeValid);

                if (_selectedArea != null &&
                    !grouped.containsKey(_selectedArea)) {
                  _selectedArea = null;
                }

                final visibleReports = _selectedArea == null
                    ? sortReportsByArea(activeValid)
                    : (grouped[_selectedArea] ?? const <ReportModel>[]);

                if (visibleReports.isNotEmpty) {
                  _maybeAutoCenter(visibleReports);
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatsHeader(
                        activeCount: activeValid.length,
                        clearedCount: clearedCount,
                        areaCount: grouped.length,
                      ),
                      const SizedBox(height: 14),
                      _buildMapCard(visibleReports),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Valid Reports by Area',
                            style: AppTypography.heading.copyWith(fontSize: 18),
                          ),
                          Text(
                            '${visibleReports.length} active',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildAreaFilterChips(grouped, activeValid.length),
                      if (validSnap.connectionState ==
                              ConnectionState.waiting &&
                          !validSnap.hasData)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (validSnap.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _EmptyReportsCard(
                            icon: Icons.cloud_off_outlined,
                            title: 'Could not load valid reports',
                            subtitle: 'Check your connection or Firestore permissions.',
                          ),
                        )
                      else if (activeValid.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: _EmptyReportsCard(
                            icon: Icons.verified_outlined,
                            title: 'No valid reports pending clearance',
                            subtitle: 'All reported mosquito breeding sites have been cleared.',
                          ),
                        )
                      else
                        for (final entry in grouped.entries)
                          if (_selectedArea == null ||
                              _selectedArea == entry.key)
                            _buildAreaSection(entry.key, entry.value),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Compact stat card at the top of the authority dashboard.
class _SummaryStatCard extends StatelessWidget {
  const _SummaryStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
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
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
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

/// Card in the area-sorted list showing one valid report's photo, category,
/// AI reason, date, "still present" count, and "Mark as cleared" action.
class _AuthorityReportCard extends StatelessWidget {
  const _AuthorityReportCard({
    super.key,
    required this.report,
    required this.area,
    required this.photoLoader,
    required this.isClearing,
    required this.onTap,
    required this.onMarkCleared,
  });

  final ReportModel report;
  final String area;
  final Future<Uint8List?> Function(String reportId) photoLoader;
  final bool isClearing;
  final VoidCallback onTap;
  final VoidCallback onMarkCleared;

  @override
  Widget build(BuildContext context) {
    final photoId = report.photoId.isNotEmpty ? report.photoId : report.id;
    final categoryLabel = SiteCategory.labelFor(report.type);
    final aiReason = (report.aiReason != null && report.aiReason!.isNotEmpty)
        ? report.aiReason!
        : (report.description.isNotEmpty
              ? report.description
              : 'Verified mosquito breeding site.');

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ReportPhotoView(
                      reportId: photoId,
                      width: 78,
                      height: 78,
                      loader: photoLoader,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                categoryLabel,
                                style: AppTypography.heading.copyWith(
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: AppBadges.successDecoration,
                              child: Text(
                                area,
                                style: AppBadges.successTextStyle.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Reported ${formatReportDate(report.createdAt)}',
                          style: AppTypography.caption,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: report.confirmationCount > 0
                              ? AppBadges.warningDecoration
                              : BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border),
                                ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.repeat_rounded,
                                size: 13,
                                color: report.confirmationCount > 0
                                    ? AppColors.warningText
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                stillPresentLabel(report.confirmationCount),
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: report.confirmationCount > 0
                                      ? AppColors.warningText
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'AI reason: $aiReason',
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: isClearing ? null : onMarkCleared,
                  icon: isClearing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    isClearing ? 'Marking as cleared...' : 'Mark as cleared',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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

/// Full report detail bottom sheet shown when a report card or map marker is
/// tapped: photo (`ReportPhotoView`), category, area, AI reason, date, how many
/// times it was marked "still present", and the "Mark as cleared" button.
class _AuthorityReportDetailSheet extends StatelessWidget {
  const _AuthorityReportDetailSheet({
    required this.report,
    required this.photoLoader,
    required this.isClearing,
    required this.onMarkCleared,
  });

  final ReportModel report;
  final Future<Uint8List?> Function(String reportId) photoLoader;
  final bool isClearing;
  final VoidCallback onMarkCleared;

  @override
  Widget build(BuildContext context) {
    final photoId = report.photoId.isNotEmpty ? report.photoId : report.id;
    final area = areaForReport(report);
    final lat = report.location.latitude != 0
        ? report.location.latitude
        : report.lat;
    final lng = report.location.longitude != 0
        ? report.location.longitude
        : report.lng;
    final aiReason = (report.aiReason != null && report.aiReason!.isNotEmpty)
        ? report.aiReason!
        : (report.description.isNotEmpty
              ? report.description
              : 'Verified mosquito breeding site.');

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
                loader: photoLoader,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    SiteCategory.labelFor(report.type),
                    style: AppTypography.heading,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: AppBadges.successDecoration,
                  child: Text(area, style: AppBadges.successTextStyle),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Reported ${formatReportDate(report.createdAt)} · '
              '${lat.toStringAsFixed(5)}° N, ${lng.toStringAsFixed(5)}° E',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: report.confirmationCount > 0
                  ? AppBadges.warningDecoration
                  : BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.repeat_rounded,
                    size: 16,
                    color: report.confirmationCount > 0
                        ? AppColors.warningText
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    stillPresentLabel(report.confirmationCount),
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: report.confirmationCount > 0
                          ? AppColors.warningText
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text('AI reason: $aiReason', style: AppTypography.body),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: isClearing ? null : onMarkCleared,
                icon: isClearing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cleaning_services_outlined, size: 18),
                label: Text(
                  isClearing ? 'Marking as cleared...' : 'Mark as cleared',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReportsCard extends StatelessWidget {
  const _EmptyReportsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryDark, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AuthorityGridPainter extends CustomPainter {
  const _AuthorityGridPainter({required this.centerWorld});

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
  bool shouldRepaint(_AuthorityGridPainter oldDelegate) =>
      oldDelegate.centerWorld != centerWorld;
}

class _AuthorityHeatmapPainter extends CustomPainter {
  const _AuthorityHeatmapPainter({required this.points});

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
  bool shouldRepaint(_AuthorityHeatmapPainter oldDelegate) =>
      oldDelegate.points != points;
}
