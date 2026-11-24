import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'insight_period.dart';

enum _ChartRange { months12, months24, years }

enum _ChartMetric { revenue, jobs }

/// Customer revenue + activity insights: headline stats, interactive bar chart
/// (tap a bar to filter Jobs/Quotes below), quote-status mix and top quotes.
class CustomerInsightPanel extends StatefulWidget {
  final List<dynamic> jobs;
  final List<dynamic> quotes;
  final InsightPeriod? selectedPeriod;
  final ValueChanged<InsightPeriod?> onPeriodSelected;

  const CustomerInsightPanel({
    super.key,
    required this.jobs,
    required this.quotes,
    required this.selectedPeriod,
    required this.onPeriodSelected,
  });

  @override
  State<CustomerInsightPanel> createState() => _CustomerInsightPanelState();
}

class _Bucket {
  final InsightPeriod period;
  double revenue = 0;
  int jobs = 0;
  int wonQuotes = 0;
  _Bucket(this.period);
}

class _CustomerInsightPanelState extends State<CustomerInsightPanel> {
  _ChartRange _range = _ChartRange.months12;
  _ChartMetric _metric = _ChartMetric.revenue;

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  static double _moneyOf(dynamic n) {
    if (n is num) return n.toDouble();
    return double.tryParse('$n') ?? 0;
  }

  static String _statusOf(dynamic record) {
    final data = record.data as Map<String, dynamic>? ?? {};
    final s = '${data['status'] ?? ''}'.trim().toLowerCase();
    return s.isEmpty ? 'draft' : s;
  }

  /// Shop create date first; fall back to PocketBase system created/updated.
  static DateTime? _quoteDate(dynamic q) {
    final data = q.data as Map<String, dynamic>? ?? {};
    final stamped = _parseDate(data['quote_created_date']);
    if (stamped != null) return stamped;
    try {
      final created = _parseDate(q.created);
      if (created != null) return created;
    } catch (_) {}
    return _parseDate(data['updated']);
  }

  static DateTime? _jobDate(dynamic job) {
    final data = job.data as Map<String, dynamic>? ?? {};
    return _parseDate(
      data['ship_date'] ??
          data['delivered_date'] ??
          data['created'] ??
          data['updated'],
    );
  }

  String _money(double v, {bool code = false}) {
    final s = NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(v);
    return code ? '$s CAD' : s;
  }

  String _compactMoney(double v) =>
      NumberFormat.compactSimpleCurrency(decimalDigits: v < 1000 ? 0 : 1)
          .format(v);

  @override
  Widget build(BuildContext context) {
    if (widget.jobs.isEmpty && widget.quotes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Insights',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Won revenue uses quote created date (CAD). Jobs use ship / created date.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        _buildStats(context),
        const SizedBox(height: 16),
        _buildChartCard(context),
        const SizedBox(height: 16),
        _buildBreakdown(context),
      ],
    );
  }

  // ---------------------------------------------------------------- stats

  Widget _buildStats(BuildContext context) {
    final now = DateTime.now();
    final sameDayLastYear = DateTime(now.year - 1, now.month, now.day, 23, 59);

    double totalWon = 0, ytd = 0, lastYtd = 0, lastYearFull = 0, pipeline = 0;
    var wonCount = 0;
    DateTime? firstWon;
    DateTime? lastActivity;

    for (final q in widget.quotes) {
      final status = _statusOf(q);
      final data = q.data as Map<String, dynamic>? ?? {};
      final amount = _moneyOf(data['final_total_cad']);
      final when = _quoteDate(q);
      if (when != null) {
        lastActivity = lastActivity == null || when.isAfter(lastActivity)
            ? when
            : lastActivity;
      }
      if (status == 'won') {
        totalWon += amount;
        wonCount++;
        if (when != null) {
          firstWon = firstWon == null || when.isBefore(firstWon) ? when : firstWon;
          if (when.year == now.year) ytd += amount;
          if (when.year == now.year - 1) {
            lastYearFull += amount;
            if (!when.isAfter(sameDayLastYear)) lastYtd += amount;
          }
        }
      } else if (status == 'draft' || status == 'sent') {
        pipeline += amount;
      }
    }

    for (final job in widget.jobs) {
      final when = _jobDate(job);
      if (when == null) continue;
      lastActivity =
          lastActivity == null || when.isAfter(lastActivity) ? when : lastActivity;
    }

    String? ytdDelta;
    if (lastYtd > 0) {
      final pct = (ytd - lastYtd) / lastYtd * 100;
      ytdDelta =
          '${pct >= 0 ? '+' : '-'}${pct.abs().toStringAsFixed(0)}% vs same point ${now.year - 1}';
    } else if (ytd > 0) {
      ytdDelta = 'No won revenue by this date in ${now.year - 1}';
    }

    String? lastAgo;
    if (lastActivity != null) {
      final days = DateTime(now.year, now.month, now.day)
          .difference(DateTime(
              lastActivity.year, lastActivity.month, lastActivity.day))
          .inDays;
      lastAgo = days <= 0
          ? 'Today'
          : days == 1
              ? 'Yesterday'
              : days < 60
                  ? '$days days ago'
                  : '${(days / 30.4).round()} months ago';
    }

    final openQuotes = widget.quotes
        .where((q) {
          final s = _statusOf(q);
          return s == 'draft' || s == 'sent';
        })
        .length;

    final cards = <Widget>[
      _StatCard(
        label: 'Won revenue',
        value: _money(totalWon, code: true),
        detail: firstWon == null
            ? (wonCount == 0 ? 'No won quotes yet' : null)
            : 'Since ${DateFormat.yMMM().format(firstWon)} · $wonCount won',
        emphasize: true,
      ),
      _StatCard(
        label: '${now.year} so far',
        value: _money(ytd),
        detail: ytdDelta,
      ),
      _StatCard(
        label: '${now.year - 1}',
        value: _money(lastYearFull),
        detail: 'Full year won',
      ),
      _StatCard(
        label: 'Open pipeline',
        value: _money(pipeline),
        detail: '$openQuotes draft/sent · ${widget.jobs.length} jobs',
      ),
      _StatCard(
        label: 'Last activity',
        value: lastActivity == null
            ? '—'
            : DateFormat.yMMMd().format(lastActivity),
        detail: lastAgo,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 900
            ? 5
            : c.maxWidth >= 560
                ? 3
                : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: w, child: card),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- chart

  List<_Bucket> _buckets() {
    final now = DateTime.now();
    final buckets = <_Bucket>[];
    if (_range == _ChartRange.years) {
      final years = <int>{};
      for (final q in widget.quotes) {
        final d = _quoteDate(q);
        if (d != null) years.add(d.year);
      }
      for (final j in widget.jobs) {
        final d = _jobDate(j);
        if (d != null) years.add(d.year);
      }
      final firstYear =
          years.isEmpty ? now.year : years.reduce(math.min);
      for (var y = math.min(firstYear, now.year - 1); y <= now.year; y++) {
        buckets.add(_Bucket(InsightPeriod.year(y)));
      }
    } else {
      final n = _range == _ChartRange.months12 ? 12 : 24;
      for (var i = n - 1; i >= 0; i--) {
        final d = DateTime(now.year, now.month - i);
        buckets.add(_Bucket(InsightPeriod.month(d.year, d.month)));
      }
    }

    for (final q in widget.quotes) {
      if (_statusOf(q) != 'won') continue;
      final when = _quoteDate(q);
      if (when == null) continue;
      final data = q.data as Map<String, dynamic>? ?? {};
      final amount = _moneyOf(data['final_total_cad']);
      for (final b in buckets) {
        if (b.period.contains(when)) {
          b.revenue += amount;
          b.wonQuotes++;
          break;
        }
      }
    }

    for (final job in widget.jobs) {
      final when = _jobDate(job);
      if (when == null) continue;
      for (final b in buckets) {
        if (b.period.contains(when)) {
          b.jobs++;
          break;
        }
      }
    }
    return buckets;
  }

  Widget _buildChartCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buckets = _buckets();
    final isRevenue = _metric == _ChartMetric.revenue;
    final values = [
      for (final b in buckets) isRevenue ? b.revenue : b.jobs.toDouble(),
    ];
    final maxY = values.fold<double>(0, math.max);
    final nonZero = values.where((v) => v > 0).toList();
    final avg = nonZero.isEmpty
        ? 0.0
        : values.fold<double>(0, (s, v) => s + v) / values.length;
    final yStep = maxY <= 0
        ? (isRevenue ? 25.0 : 1.0)
        : _niceStep(maxY * 1.08 / 4);
    final yMax = yStep * 4;
    final selected = widget.selectedPeriod;
    final now = DateTime.now();
    final barWidth = switch (_range) {
      _ChartRange.months12 => 16.0,
      _ChartRange.months24 => 9.0,
      _ChartRange.years => buckets.length > 8 ? 14.0 : 26.0,
    };

    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    isRevenue
                        ? (_range == _ChartRange.years
                            ? 'Won revenue by year'
                            : 'Monthly won revenue')
                        : (_range == _ChartRange.years
                            ? 'Jobs by year'
                            : 'Monthly jobs'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SegmentedButton<_ChartMetric>(
                      segments: const [
                        ButtonSegment(
                          value: _ChartMetric.revenue,
                          label: Text('Revenue'),
                        ),
                        ButtonSegment(
                          value: _ChartMetric.jobs,
                          label: Text('Jobs'),
                        ),
                      ],
                      selected: {_metric},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (s) =>
                          setState(() => _metric = s.first),
                    ),
                    SegmentedButton<_ChartRange>(
                      segments: const [
                        ButtonSegment(
                          value: _ChartRange.months12,
                          label: Text('12 mo'),
                        ),
                        ButtonSegment(
                          value: _ChartRange.months24,
                          label: Text('24 mo'),
                        ),
                        ButtonSegment(
                          value: _ChartRange.years,
                          label: Text('Yearly'),
                        ),
                      ],
                      selected: {_range},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (s) =>
                          setState(() => _range = s.first),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: yMax,
                  minY: 0,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: yStep,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (avg > 0)
                        HorizontalLine(
                          y: avg,
                          color: scheme.secondary.withValues(alpha: 0.7),
                          strokeWidth: 1.2,
                          dashArray: const [5, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                            labelResolver: (_) => isRevenue
                                ? 'avg ${_compactMoney(avg)}'
                                : 'avg ${avg.toStringAsFixed(avg < 10 ? 1 : 0)}',
                          ),
                        ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: yStep,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max) return const SizedBox();
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              isRevenue
                                  ? _compactMoney(value)
                                  : value.toStringAsFixed(
                                      value == value.roundToDouble() ? 0 : 1),
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= buckets.length) {
                            return const SizedBox();
                          }
                          final label = _bottomLabel(buckets, i);
                          if (label == null) return const SizedBox();
                          return SideTitleWidget(
                            meta: meta,
                            space: 6,
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.15,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => scheme.inverseSurface,
                      tooltipBorderRadius: BorderRadius.circular(8),
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      maxContentWidth: 170,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final b = buckets[group.x];
                        final primary = isRevenue
                            ? _money(b.revenue)
                            : '${b.jobs} job${b.jobs == 1 ? '' : 's'}';
                        final secondary = isRevenue
                            ? '${b.wonQuotes} won · ${b.jobs} job${b.jobs == 1 ? '' : 's'}'
                            : '${b.wonQuotes} won · ${_money(b.revenue)}';
                        final canFilter = isRevenue
                            ? (b.wonQuotes > 0 || b.jobs > 0)
                            : b.jobs > 0;
                        return BarTooltipItem(
                          '${b.period.label}\n',
                          TextStyle(
                            color: scheme.onInverseSurface,
                            fontSize: 11,
                          ),
                          children: [
                            TextSpan(
                              text: primary,
                              style: TextStyle(
                                color: scheme.onInverseSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '\n$secondary${canFilter ? ' · tap to filter' : ''}',
                              style: TextStyle(
                                color: scheme.onInverseSurface
                                    .withValues(alpha: 0.75),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final i = response?.spot?.touchedBarGroupIndex;
                      if (i == null || i < 0 || i >= buckets.length) return;
                      final b = buckets[i];
                      final canFilter = isRevenue
                          ? (b.wonQuotes > 0 || b.jobs > 0)
                          : b.jobs > 0;
                      if (!canFilter) return;
                      widget.onPeriodSelected(
                        selected == b.period ? null : b.period,
                      );
                    },
                  ),
                  barGroups: [
                    for (var i = 0; i < buckets.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: values[i],
                            width: barWidth,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                            color: _barColor(
                              scheme,
                              buckets[i].period,
                              selected,
                              isCurrent: buckets[i].period.contains(now),
                            ),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: yMax,
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 250),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              nonZero.isEmpty
                  ? (isRevenue
                      ? 'No won revenue in this range.'
                      : 'No jobs in this range.')
                  : 'Tap a bar to filter Jobs and Quotes below. Dashed line = average.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Color _barColor(
    ColorScheme scheme,
    InsightPeriod period,
    InsightPeriod? selected, {
    required bool isCurrent,
  }) {
    if (selected != null) {
      return period == selected
          ? scheme.primary
          : scheme.primary.withValues(alpha: 0.25);
    }
    return isCurrent
        ? scheme.primary
        : Color.lerp(scheme.primary, scheme.surface, 0.25)!;
  }

  String? _bottomLabel(List<_Bucket> buckets, int i) {
    final p = buckets[i].period;
    if (p.month == null) return '${p.year}';
    final m = DateFormat.MMM().format(DateTime(p.year, p.month!));
    final showYear = i == 0 || p.month == 1;
    if (_range == _ChartRange.months24 && i % 3 != 0 && p.month != 1) {
      return null;
    }
    final short = _range == _ChartRange.months24 ? m.substring(0, 1) : m;
    final yy = (p.year % 100).toString().padLeft(2, '0');
    return showYear ? "$short\n'$yy" : short;
  }

  double _niceStep(double v) {
    if (v <= 0) return 1;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in const [1, 2, 2.5, 5, 10]) {
      if (m * exp >= v) return m * exp;
    }
    return 10 * exp;
  }

  // ------------------------------------------------------------ breakdown

  Widget _buildBreakdown(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selectedPeriod;
    final scopeLabel = selected?.label ?? 'All time';

    Widget card(String title, Widget child) => Card.outlined(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      scopeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        );

    final scopedQuotes = widget.quotes.where((q) {
      if (selected == null) return true;
      final when = _quoteDate(q);
      return when != null && selected.contains(when);
    }).toList();

    const statusOrder = ['won', 'sent', 'draft', 'lost'];
    const statusLabels = {
      'won': 'Won',
      'sent': 'Sent',
      'draft': 'Draft',
      'lost': 'Lost',
    };
    final statusColors = {
      'won': scheme.primary,
      'sent': Color.lerp(scheme.primary, scheme.onSurface, 0.35)!,
      'draft': Color.lerp(scheme.primary, scheme.surface, 0.55)!,
      'lost': scheme.onSurfaceVariant,
    };

    final byStatus = <String, double>{};
    final countByStatus = <String, int>{};
    for (final q in scopedQuotes) {
      final s = _statusOf(q);
      final key = statusOrder.contains(s) ? s : 'draft';
      final data = q.data as Map<String, dynamic>? ?? {};
      byStatus[key] = (byStatus[key] ?? 0) + _moneyOf(data['final_total_cad']);
      countByStatus[key] = (countByStatus[key] ?? 0) + 1;
    }
    final statusTotal = byStatus.values.fold<double>(0, (s, v) => s + v);

    final statusCard = card(
      'Quotes by status',
      statusTotal <= 0 && countByStatus.isEmpty
          ? _emptyNote(context, 'No quotes in this period.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (statusTotal > 0)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        children: [
                          for (final t in statusOrder)
                            if ((byStatus[t] ?? 0) > 0)
                              Expanded(
                                flex: math.max(
                                    1, (byStatus[t]! / statusTotal * 1000).round()),
                                child: Tooltip(
                                  message: statusLabels[t]!,
                                  child: Container(color: statusColors[t]),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                if (statusTotal > 0) const SizedBox(height: 12),
                for (final t in statusOrder)
                  if ((countByStatus[t] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: statusColors[t],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${statusLabels[t]!} (${countByStatus[t]})',
                            ),
                          ),
                          if (statusTotal > 0)
                            Text(
                              '${(byStatus[t]! / statusTotal * 100).toStringAsFixed(0)}%',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 96,
                            child: Text(
                              _money(byStatus[t] ?? 0),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
    );

    final ranked = [...scopedQuotes]..sort((a, b) {
        final ad = a.data as Map<String, dynamic>? ?? {};
        final bd = b.data as Map<String, dynamic>? ?? {};
        return _moneyOf(bd['final_total_cad'])
            .compareTo(_moneyOf(ad['final_total_cad']));
      });

    final topCard = card(
      'Top quotes',
      ranked.isEmpty
          ? _emptyNote(context, 'No quotes in this period.')
          : Column(
              children: [
                for (final q in ranked.take(6)) _topQuoteRow(context, q),
                if (ranked.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+ ${ranked.length - 6} more quotes',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [statusCard, const SizedBox(height: 16), topCard],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: statusCard),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: topCard),
          ],
        );
      },
    );
  }

  Widget _topQuoteRow(BuildContext context, dynamic q) {
    final scheme = Theme.of(context).colorScheme;
    final data = q.data as Map<String, dynamic>? ?? {};
    final jobNumber = '${data['job_number'] ?? ''}'.trim();
    final status = _statusOf(q);
    final amount = _moneyOf(data['final_total_cad']);
    final when = _quoteDate(q);
    final title = jobNumber.isEmpty ? 'Quote' : jobNumber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  [
                    status[0].toUpperCase() + status.substring(1),
                    if (when != null) DateFormat.yMMMd().format(when),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _money(amount),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _emptyNote(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final bool emphasize;

  const _StatCard({
    required this.label,
    required this.value,
    this.detail,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: emphasize
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize ? Colors.transparent : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: emphasize
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: emphasize ? scheme.onPrimaryContainer : null,
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: emphasize
                    ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
