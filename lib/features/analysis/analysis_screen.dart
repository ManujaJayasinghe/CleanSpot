import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme_proposal.dart';
import '../profile/widgets/info_note.dart';
import '../profile/widgets/tip_banner.dart';
import 'analysis_notes.dart';
import 'dengue_analysis.dart';
import 'dengue_repository.dart';

/// Dengue Analysis screen: weekly cases per district, the top districts this
/// year, and short written insights.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late final Future<DengueData> _data;
  String? _district;

  @override
  void initState() {
    super.initState();
    _data = DengueRepository().load();
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
                      const Text('Select district', style: AppTypography.heading),
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
                          name,
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
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
        child: FutureBuilder<DengueData>(
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

  List<Widget> _buildBody(AsyncSnapshot<DengueData> snapshot) {
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

    final data = snapshot.data!;
    final stats = data.stats;
    final districts = districtsOf(stats);
    final year = latestYear(stats);
    if (districts.isEmpty || year == null) {
      return const [
        SizedBox(height: 40),
        _Notice(icon: Icons.inbox_outlined, text: 'No dengue data to show yet.'),
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

    return [
      InfoNote(
        text: data.isSample
            ? 'Sample data only · NOT real statistics. Add the real CSV to replace it.'
            : 'Weekly dengue cases by district · latest data: $year',
        icon: data.isSample ? Icons.warning_amber_rounded : Icons.info_outline,
      ),
      const SizedBox(height: 20),
      _DistrictSelector(
        name: district,
        onTap: () => _showDistrictPicker(districts, totals),
      ),
      const SizedBox(height: 20),
      _ChartCard(
        title: 'Weekly dengue cases',
        subtitle: '$district · all weeks in the data',
        child: SizedBox(
          height: 200,
          child: _WeeklyCasesChart(series: series),
        ),
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
        'Insights for $district',
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
          footnote: note.source == null
              ? 'Draft note · Source pending'
              : 'Source: ${note.source}',
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 8),
      const TipBanner(
        text: 'Prevention insight: Eliminating stagnant water weekly breaks '
            'the 7-day Aedes mosquito breeding cycle.',
      ),
      const SizedBox(height: 20),
    ];
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
            Text(
              name,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
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
double _niceMax(num value) => (((value / 4).ceil()).clamp(1, 1 << 30) * 4).toDouble();

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
                      top[i].district,
                      style: _axisStyle.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
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
              '${top[groupIndex].district}\n${rod.toY.round()} cases',
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
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
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
