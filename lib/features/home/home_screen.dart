import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../ai_validation/validation_result.dart';
import '../map/risk_map_preview.dart';
import '../profile/current_user.dart';
import '../profile/widgets/widgets.dart';

/// CleanSpot Home Dashboard screen.
///
/// From top to bottom: greeting, available points, the live risk map preview,
/// the Report button, and the latest report. The map takes all the leftover
/// height, so on a tall phone the page fills the screen and Recent reports sits
/// just above the navigation bar. On a short screen or with large text, where
/// the content does not fit, the whole page scrolls instead (the map keeps a
/// minimum height of [minMapHeight]).
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.user,
    this.pointsStream,
    this.mapReports,
    this.recentReports,
  });

  /// Overrides for tests. They default to the signed-in user and the live
  /// Firestore streams.
  final CurrentUser? user;
  final Stream<UserModel?>? pointsStream;
  final Stream<List<ReportModel>>? mapReports;
  final Stream<List<ReportModel>>? recentReports;

  /// The map never gets shorter than this; the page scrolls instead.
  static const double minMapHeight = 240;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = this.user ?? CurrentUser.fromAuth();
    final firstName = user.firstName;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Fills the viewport when the content is shorter than it, so the
            // Expanded map can use the leftover height. When the content is
            // taller, the page scrolls.
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Greeting & Avatar Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, $firstName',
                                style: (textTheme.headlineSmall ?? AppTypography.title).copyWith(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'A small action can protect a whole street.',
                                style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // User Avatar
                        InkWell(
                          onTap: () => context.go('/profile'),
                          borderRadius: BorderRadius.circular(24),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.primaryLight,
                            backgroundImage: user.photoUrl != null &&
                                    user.photoUrl!.isNotEmpty
                                ? NetworkImage(user.photoUrl!)
                                : null,
                            child: user.photoUrl == null ||
                                    user.photoUrl!.isEmpty
                                ? Text(
                                    user.initials,
                                    style: const TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryDark,
                                      fontSize: 16,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Available points (compact, same style as the Rewards card)
                    _AvailablePointsCard(stream: pointsStream),
                    const SizedBox(height: 12),

                    // Live risk map preview: takes all the leftover height.
                    Expanded(
                      child: _MinHeightSlot(
                        minHeight: minMapHeight,
                        child: RiskMapPreview(reports: mapReports),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // "Report a Breeding Site" action button
                    const _ReportButton(),
                    const SizedBox(height: 12),

                    // Recent Reports Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Recent reports',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (textTheme.titleLarge ?? AppTypography.heading).copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/profile/reports'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'View all',
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Real latest report card from Firestore
                    LatestReportCard(reports: recentReports),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "AVAILABLE POINTS" card in the leaf style of the Rewards balance
/// card: label, live number and "points" in one row, about 80 px tall.
class _AvailablePointsCard extends StatelessWidget {
  const _AvailablePointsCard({this.stream});

  final Stream<UserModel?>? stream;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LeafBackground(
      key: const ValueKey('home-points-card'),
      borderRadius: BorderRadius.circular(20),
      circleSize: 150,
      circleTop: null,
      circleRight: -48,
      leafSize: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AVAILABLE POINTS',
              style: (textTheme.labelSmall ?? AppTypography.caption).copyWith(
                color: AppColors.surface.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            UserPoints(
              stream: stream,
              builder: (context, points) => Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      '$points',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (textTheme.displayLarge ?? AppTypography.pointsBig).copyWith(
                        color: AppColors.surface,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'points',
                    style: (textTheme.bodyLarge ?? AppTypography.body).copyWith(
                      color: AppColors.surface.withValues(alpha: 0.85),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width "Report a Breeding Site" button: a plain solid
/// [AppColors.primary] fill (no decoration), so the normal button ripple works.
class _ReportButton extends StatelessWidget {
  const _ReportButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        key: const ValueKey('home-report-button'),
        onPressed: () => context.go('/report'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        // FittedBox: the label shrinks instead of overflowing on a narrow
        // screen or with very large text.
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, size: 22),
              SizedBox(width: 8),
              Text(
                'Report a Breeding Site',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reports a fixed minimum height for its child when the page measures its
/// content, and otherwise lays the child out with whatever space it is given.
///
/// The Home page fills the screen with `SliverFillRemaining`, which asks its
/// content for an intrinsic height. The map ([RiskMapPreview] and
/// `LayoutBuilder`) cannot answer that, so this slot answers for it: "I need at
/// least [minHeight]". The `Expanded` around it then stretches it to the
/// leftover space.
class _MinHeightSlot extends SingleChildRenderObjectWidget {
  const _MinHeightSlot({required this.minHeight, required super.child});

  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMinHeightSlot(minHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMinHeightSlot renderObject,
  ) {
    renderObject.minHeight = minHeight;
  }
}

class _RenderMinHeightSlot extends RenderProxyBox {
  _RenderMinHeightSlot(this._minHeight);

  double _minHeight;

  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _minHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => _minHeight;

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
        Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 0,
          constraints.hasBoundedHeight ? constraints.maxHeight : _minHeight,
        ),
      );
}

/// Displays the current user's most recent breeding site report from Firestore,
/// or an empty state prompting them to make their first report.
class LatestReportCard extends StatefulWidget {
  const LatestReportCard({super.key, this.reports});

  /// Report stream override, for tests. Defaults to the signed-in user's reports.
  final Stream<List<ReportModel>>? reports;

  @override
  State<LatestReportCard> createState() => _LatestReportCardState();
}

class _LatestReportCardState extends State<LatestReportCard> {
  Stream<List<ReportModel>>? _stream;

  @override
  void initState() {
    super.initState();
    if (widget.reports != null) {
      _stream = widget.reports;
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _stream = FirestoreService().watchUserReports(uid);
    }
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<List<ReportModel>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _cardDecoration,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final reports = snapshot.data ?? [];
        if (reports.isEmpty) {
          return InkWell(
            onTap: () => context.go('/report'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: _cardDecoration,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryLight,
                    ),
                    child: const Icon(
                      Icons.add_location_alt_outlined,
                      color: AppColors.primaryDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No reports yet',
                          style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Tap to report your first breeding site.',
                          style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 13,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          );
        }

        final latest = reports.first;
        final locationText = latest.description.isNotEmpty
            ? latest.description
            : '${latest.lat.toStringAsFixed(4)}° N, ${latest.lng.toStringAsFixed(4)}° E';
        final detailStyle = (textTheme.bodySmall ?? AppTypography.caption).copyWith(
          fontSize: 12,
          color: AppColors.textSecondary,
        );

        return InkWell(
          onTap: () => context.push('/profile/reports'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: _cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        SiteCategory.labelFor(latest.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip.fromStatus(
                      text: latest.status,
                      status: latest.status,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Coordinates and date share a line when they fit, and wrap
                // onto a second line when they do not.
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    Text(locationText, style: detailStyle),
                    Text(_formatDate(latest.createdAt), style: detailStyle),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static final BoxDecoration _cardDecoration = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.border, width: 1),
  );
}
