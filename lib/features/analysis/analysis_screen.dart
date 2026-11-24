import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme_proposal.dart';
import '../../services/firestore_service.dart';
import '../profile/widgets/info_note.dart';
import '../profile/widgets/tip_banner.dart';
import 'analysis_notes.dart';
import 'dengue_analysis.dart';
import 'dengue_repository.dart';
import 'dengue_stat.dart';
import 'risk_constants.dart';
import 'risk_index.dart';
import 'waste_period.dart';

/// Everything the screen needs from the bundled data files.
class _AnalysisData {
  const _AnalysisData(this.dengue, this.periods);

  final DengueData dengue;
  final List<WastePeriod> periods;
}

/// Dengue Analysis screen: the seasonal risk index, weekly cases per district,
/// the top districts this year, and short written insights.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, this.liveReports, this.clock, this.bundle});

  /// Valid CleanSpot reports as they change. Defaults to the live Firestore
  /// stream of valid reports; tests pass their own.
  final Stream<List<LiveReport>>? liveReports;

  /// Where the CSV files are loaded from. Defaults to the app's assets.
  final AssetBundle? bundle;

  /// What "today" is. Defaults to the device clock; tests pass a fixed date.
  final DateTime Function()? clock;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late final Future<_AnalysisData> _data;
  StreamSubscription<List<LiveReport>>? _liveSub;

  /// Valid reports from the last snapshot; null until the first one arrives
  /// or when they cannot be loaded (then the index simply leaves them out).
  List<LiveReport>? _live;
  String? _district;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _data = _load();
    _liveSub = (widget.liveReports ?? _firestoreReports()).listen(
      (reports) {
        if (mounted) setState(() => _live = reports);
      },
      onError: (Object _) {
        if (mounted) setState(() => _live = null);
      },
    );
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  Future<_AnalysisData> _load() async {
    final dengue = await DengueRepository(bundle: widget.bundle).load();
    final periods = await WastePeriodRepository(bundle: widget.bundle).load();
    return _AnalysisData(dengue, periods);
  }

  /// The live stream of valid reports. If Firebase is not available (for
  /// example in a test) there are no live reports, and the index says so.
  Stream<List<LiveReport>> _firestoreReports() {
    try {
      return FirestoreService().watchValidReports().map(
        (reports) => [
          for (final r in reports)
            LiveReport(lat: r.lat, lng: r.lng, createdAt: r.createdAt),
        ],
      );
    } catch (_) {
      return const Stream.empty();
    }
  }

  void _showDistrictPicker(List<String> districts, Map<String, int> totals) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select district',
                        style: AppTypography.heading,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: districts.length,
                    itemBuilder: (_, index) {
                      final name = districts[index];
                      final selected = name == _district;
                      return ListTile(
                        leading: Icon(
                          Icons.location_on_outlined,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        title: Text(
                          displayDistrictName(name),
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: selected
                                ? AppColors.primaryDark
                                : AppColors.textPrimary,
                          ),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check, color: AppColors.primary)
                            : Text(
                                '${totals[name] ?? 0} cases',
                                style: AppTypography.caption,
                              ),
                        onTap: () {
                          setState(() => _district = name);
                          Navigator.pop(sheetContext);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
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
        child: FutureBuilder<_AnalysisData>(
          future: _data,
          builder: (context, snapshot) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppColors.primary,
                          size: 26,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/home');
                          }
                        },
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Dengue Analysis',
                          style:
                              (textTheme.headlineMedium ?? AppTypography.title)
                                  .copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Understand patterns. Stay prepared.',
                    style: AppTypography.body,
                  ),
                  const SizedBox(height: 12),
                  ..._buildBody(snapshot),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildBody(AsyncSnapshot<_AnalysisData> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const [
        SizedBox(height: 80),
        Center(child: CircularProgressIndicator()),
      ];
    }
    if (snapshot.hasError) {
      return [
        const SizedBox(height: 40),
        _Notice(
          icon: Icons.error_outline,
          text: 'Could not load the dengue data.\n${snapshot.error}',
        ),
      ];
    }

    final loaded = snapshot.data!;
    final data = loaded.dengue;
    final stats = data.stats;
    final districts = districtsOf(stats);
    final year = latestYear(stats);
    if (districts.isEmpty || year == null) {
      return const [
        SizedBox(height: 40),
        _Notice(
          icon: Icons.inbox_outlined,
          text: 'No dengue data to show yet.',
        ),
      ];
    }

    final district = districts.contains(_district)
        ? _district!
        : (districts.contains('Colombo') ? 'Colombo' : districts.first);
    final totals = {
      for (final t in topDistricts(stats, year, limit: districts.length))
        t.district: t.cases,
    };
    final series = weeklySeries(stats, district);
    final top = topDistricts(stats, year);
    final insights = buildInsights(stats, district);

    final now = _now();
    final risks = computeRisks(
      stats: stats,
      today: now,
      periods: loaded.periods,
      liveReportCounts: _live == null ? null : countLiveReports(_live!, now),
    );

    return [
      InfoNote(
        text: data.isSample
            ? 'Sample data only · NOT real statistics. The real CSV '
                  '(assets/data/dengue_stats.csv) is missing; see '
                  'docs/ANALYSIS_DATA.md.'
            : dataStatusText(stats, now),
        icon: data.isSample ? Icons.warning_amber_rounded : Icons.info_outline,
      ),
      const SizedBox(height: 20),
      _DistrictSelector(
        name: displayDistrictName(district),
        onTap: () => _showDistrictPicker(districts, totals),
      ),
      const SizedBox(height: 20),
      _RiskSection(
        risks: risks,
        selected: district,
        today: now,
        liveAvailable: _live != null,
      ),
      const SizedBox(height: 20),
      _ChartCard(
        title: 'Weekly dengue cases',
        subtitle: '${displayDistrictName(district)} · all weeks in the data',
        child: SizedBox(height: 200, child: _WeeklyCasesChart(series: series)),
      ),
      const SizedBox(height: 20),
      _ChartCard(
        title: 'Top ${top.length} districts in $year',
        subtitle: 'Total cases this year',
        child: SizedBox(
          height: 280,
          child: _TopDistrictsChart(top: top, selected: district),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'Insights for ${displayDistrictName(district)}',
        style: AppTypography.heading.copyWith(fontSize: 18),
      ),
      const SizedBox(height: 10),
      for (final insight in insights) ...[
        _InsightCard(title: insight.title, body: insight.body),
        const SizedBox(height: 12),
      ],
      for (final note in writtenInsights) ...[
        _InsightCard(
          title: note.title,
          body: note.text,
          footnote: [
            for (final s in note.sources) 'Source: ${s.label}\n${s.url}',
          ].join('\n'),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 8),
      const TipBanner(
        text:
            'Prevention insight: Eliminating stagnant water weekly breaks '
            'the 7-day Aedes mosquito breeding cycle.',
      ),
      const SizedBox(height: 20),
    ];
  }
}

/// The one-line note under the title that says where the data comes from and
/// how recent it is, worked out from the loaded rows.
///
/// Example: "Historical data: Epidemiology Unit WER, 2024 – 2025 (latest: 2025
/// week 52). 2026 reports not yet available."
String dataStatusText(List<DengueStat> stats, DateTime today) {
  final years = {for (final s in stats) s.year}.toList()..sort();
  final lastYear = years.last;
  final lastWeek = stats
      .where((s) => s.year == lastYear)
      .map((s) => s.week)
      .reduce((a, b) => a > b ? a : b);
  final range = years.first == lastYear
      ? '${years.first}'
      : '${years.first} – $lastYear';
  final text =
      'Historical data: Epidemiology Unit WER, $range '
      '(latest: $lastYear week $lastWeek).';
  return lastYear < today.year
      ? '$text ${today.year} reports not yet available.'
      : text;
}

Color _levelColor(RiskLevel level) => switch (level) {
  RiskLevel.low => AppColors.success,
  RiskLevel.medium => AppColors.warning,
  RiskLevel.high => AppColors.error,
};

Color _levelBackground(RiskLevel level) => switch (level) {
  RiskLevel.low => AppColors.successBg,
  RiskLevel.medium => AppColors.warningBg,
  RiskLevel.high => AppColors.errorBg,
};

class _LevelChip extends StatelessWidget {
  const _LevelChip(this.level);

  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _levelBackground(level),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        level.label,
        style: AppTypography.caption.copyWith(
          color: _levelColor(level),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Seasonal dengue risk for today: the selected district up front, every
/// district in a list, and a short note on how the index works.
class _RiskSection extends StatelessWidget {
  const _RiskSection({
    required this.risks,
    required this.selected,
    required this.today,
    required this.liveAvailable,
  });

  final List<DistrictRisk> risks;
  final String selected;
  final DateTime today;
  final bool liveAvailable;

  @override
  Widget build(BuildContext context) {
    final current = risks.firstWhere(
      (r) => r.district == selected,
      orElse: () => risks.first,
    );

    // A Material (not a decorated Container) so the ExpansionTiles inside can
    // paint their ink on it.
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seasonal dengue risk',
              style: AppTypography.heading.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Today · week ${isoWeek(today)} of ${today.year}',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LevelChip(current.level),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayDistrictName(current.district),
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        current.reason,
                        style: AppTypography.body.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!liveAvailable) ...[
              const SizedBox(height: 8),
              const Text(
                'Live CleanSpot reports are not available right now, so they '
                'are left out of the index.',
                style: AppTypography.caption,
              ),
            ],
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: Column(
                children: [
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'All districts (${risks.length})',
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    children: [
                      for (final r in risks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 72, child: _LevelChip(r.level)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayDistrictName(r.district),
                                      style: AppTypography.body.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      r.reason,
                                      style: AppTypography.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'How the risk index works',
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'The index compares today\'s week of the year with the '
                        'same weeks in past years of Epidemiology Unit data. It '
                        'is a seasonal pattern, not a forecast.\n\n'
                        '1. Usual level: the district\'s average weekly cases '
                        'for this week and the weeks either side, over all '
                        'years in the data, divided by its average over every '
                        'week. Below $seasonalLowBelow is Low, up to '
                        '$seasonalHighAbove is Medium, above is High.\n'
                        '2. One level up if today is inside a high-waste period '
                        'with a published source for that district.\n'
                        '3. One level up if more than $liveReportsBumpAbove '
                        'valid CleanSpot reports came from the district in the '
                        'last $liveReportWindowDays days. Reports are placed in '
                        'the nearest district centre, which is approximate.\n\n'
                        'Counts are reported cases only, and the latest weeks '
                        'can be revised.',
                        style: AppTypography.body.copyWith(fontSize: 13),
                      ),
                    ],
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

class _DistrictSelector extends StatelessWidget {
  const _DistrictSelector({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.heading.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTypography.caption),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.title, required this.body, this.footnote});

  final String title;
  final String body;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: AppTypography.body.copyWith(fontSize: 13)),
          if (footnote != null) ...[
            const SizedBox(height: 8),
            Text(footnote!, style: AppTypography.caption),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }
}

/// Rounds [value] up to a multiple of 4 (at least 4) so the four grid
/// intervals are whole numbers.
double _niceMax(num value) =>
    (((value / 4).ceil()).clamp(1, 1 << 30) * 4).toDouble();

TextStyle get _axisStyle => AppTypography.caption.copyWith(fontSize: 11);

/// Line chart of weekly cases, oldest week on the left.
class _WeeklyCasesChart extends StatelessWidget {
  const _WeeklyCasesChart({required this.series});

  final List<WeekPoint> series;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return const Center(child: Text('No data', style: AppTypography.caption));
    }

    final maxCases = series.map((p) => p.cases).reduce((a, b) => a > b ? a : b);
    final maxY = _niceMax(maxCases);
    final lastIndex = series.length - 1;
    final labelEvery = (series.length / 4).ceil().clamp(1, series.length);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: lastIndex < 1 ? 1 : lastIndex.toDouble(),
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(value.round().toString(), style: _axisStyle),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: labelEvery.toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i > lastIndex) return const SizedBox.shrink();
                final p = series[i];
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    'W${p.week} \'${(p.year % 100).toString().padLeft(2, '0')}',
                    style: _axisStyle,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.primaryDark,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  'Week ${series[s.x.round()].week}, ${series[s.x.round()].year}\n'
                  '${series[s.x.round()].cases} cases',
                  const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.surface,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < series.length; i++)
                FlSpot(i.toDouble(), series[i].cases.toDouble()),
            ],
            color: AppColors.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primaryLight.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar chart of the districts with the most cases this year.
class _TopDistrictsChart extends StatelessWidget {
  const _TopDistrictsChart({required this.top, required this.selected});

  final List<DistrictTotal> top;
  final String selected;

  @override
  Widget build(BuildContext context) {
    if (top.isEmpty) {
      return const Center(child: Text('No data', style: AppTypography.caption));
    }

    final maxY = _niceMax(top.first.cases);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(value.round().toString(), style: _axisStyle),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 84,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                final isSelected = top[i].district == selected;
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      displayDistrictName(top[i].district),
                      style: _axisStyle.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.primaryDark,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
                  '${displayDistrictName(top[groupIndex].district)}\n'
                  '${rod.toY.round()} cases',
                  const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.surface,
                  ),
                ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: top[i].cases.toDouble(),
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  color: top[i].district == selected
                      ? AppColors.primaryDark
                      : AppColors.primary,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
