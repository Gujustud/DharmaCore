import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';

/// A calendar month (`month` set) or whole year (`month` null) of spend.
@immutable
class SpendPeriod {
  final int year;
  final int? month;

  const SpendPeriod.year(this.year) : month = null;
  const SpendPeriod.month(this.year, int this.month);

  bool contains(DateTime d) =>
      d.year == year && (month == null || d.month == month);

  String get label => month == null
      ? '$year'
      : DateFormat.yMMM().format(DateTime(year, month!));

  @override
  bool operator ==(Object other) =>
      other is SpendPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

enum _ChartRange { months12, months24, years }

/// Purchase-spend summary for one supplier: headline stats, an interactive
/// bar chart (tap a bar to filter the purchase list), spend by line type and
/// top items. CAD and USD are never mixed — there is no FX conversion.
class SupplierSpendPanel extends StatefulWidget {
  final List<Purchase> purchases;

  /// Line items for [purchases]; null while loading.
  final List<PurchaseItem>? items;
  final SpendPeriod? selectedPeriod;
  final ValueChanged<SpendPeriod?> onPeriodSelected;

  const SupplierSpendPanel({
    super.key,
    required this.purchases,
    required this.items,
    required this.selectedPeriod,
    required this.onPeriodSelected,
  });

  @override
  State<SupplierSpendPanel> createState() => _SupplierSpendPanelState();
}

class _Bucket {
  final SpendPeriod period;
  double total = 0;
  int orders = 0;
  _Bucket(this.period);
}

class _SupplierSpendPanelState extends State<SupplierSpendPanel> {
  String? _currency;
  _ChartRange _range = _ChartRange.months12;

  List<String> get _currencies {
    final counts = <String, int>{};
    for (final p in widget.purchases) {
      counts[p.currency] = (counts[p.currency] ?? 0) + 1;
    }
    final list = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return list;
  }

  String get _activeCurrency {
    final all = _currencies;
    if (_currency != null && all.contains(_currency)) return _currency!;
    return all.isEmpty ? 'CAD' : all.first;
  }

  List<Purchase> get _inCurrency =>
      widget.purchases.where((p) => p.currency == _activeCurrency).toList();

  String _money(double v, {bool code = false}) {
    final s = NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(v);
    return code ? '$s $_activeCurrency' : s;
  }

  String _compactMoney(double v) =>
      NumberFormat.compactSimpleCurrency(decimalDigits: v < 1000 ? 0 : 1)
          .format(v);

  @override
  Widget build(BuildContext context) {
    if (widget.purchases.isEmpty) return const SizedBox.shrink();
    final currencies = _currencies;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Spend',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (currencies.length > 1)
              SegmentedButton<String>(
                segments: [
                  for (final c in currencies)
                    ButtonSegment(value: c, label: Text(c)),
                ],
                selected: {_activeCurrency},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                onSelectionChanged: (s) =>
                    setState(() => _currency = s.first),
              ),
          ],
        ),
        if (currencies.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'CAD and USD are totalled separately (no exchange conversion).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
    final list = _inCurrency;
    final withTotal = list.where((p) => p.total != null).toList();
    final total = withTotal.fold<double>(0, (s, p) => s + p.total!);
    final now = DateTime.now();
    final sameDayLastYear = DateTime(now.year - 1, now.month, now.day, 23, 59);

    double ytd = 0, lastYtd = 0, lastYearFull = 0;
    for (final p in withTotal) {
      final d = p.purchaseDate;
      if (d.year == now.year) ytd += p.total!;
      if (d.year == now.year - 1) {
        lastYearFull += p.total!;
        if (!d.isAfter(sameDayLastYear)) lastYtd += p.total!;
      }
    }

    final dates = list.map((p) => p.purchaseDate).toList()..sort();
    final first = dates.isEmpty ? null : dates.first;
    final last = dates.isEmpty ? null : dates.last;
    final avg = withTotal.isEmpty ? 0.0 : total / withTotal.length;

    String? ytdDelta;
    Color? ytdDeltaColor;
    final scheme = Theme.of(context).colorScheme;
    if (lastYtd > 0) {
      final pct = (ytd - lastYtd) / lastYtd * 100;
      ytdDelta =
          '${pct >= 0 ? '+' : '-'}${pct.abs().toStringAsFixed(0)}% vs same point ${now.year - 1}';
      ytdDeltaColor = scheme.onSurface;
    } else if (ytd > 0) {
      ytdDelta = 'No spend by this date in ${now.year - 1}';
    }

    String? lastAgo;
    if (last != null) {
      final days = DateTime(now.year, now.month, now.day)
          .difference(DateTime(last.year, last.month, last.day))
          .inDays;
      lastAgo = days <= 0
          ? 'Today'
          : days == 1
              ? 'Yesterday'
              : days < 60
                  ? '$days days ago'
                  : '${(days / 30.4).round()} months ago';
    }

    final missing = list.length - withTotal.length;
    final cards = <Widget>[
      _StatCard(
        label: 'Total spent',
        value: _money(total, code: true),
        detail: first == null
            ? null
            : 'Since ${DateFormat.yMMM().format(first)}'
                '${missing > 0 ? ' · $missing without total' : ''}',
        emphasize: true,
      ),
      _StatCard(
        label: '${now.year} so far',
        value: _money(ytd),
        detail: ytdDelta,
        detailColor: ytdDeltaColor,
      ),
      _StatCard(
        label: '${now.year - 1}',
        value: _money(lastYearFull),
        detail: 'Full year',
      ),
      _StatCard(
        label: 'Orders',
        value: '${list.length}',
        detail: 'Avg ${_money(avg)}',
      ),
      _StatCard(
        label: 'Last purchase',
        value: last == null ? '—' : DateFormat.yMMMd().format(last),
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
    final list = _inCurrency.where((p) => p.total != null);
    final now = DateTime.now();
    final buckets = <_Bucket>[];
    if (_range == _ChartRange.years) {
      final years = list.map((p) => p.purchaseDate.year);
      final firstYear = years.isEmpty ? now.year : years.reduce(math.min);
      for (var y = math.min(firstYear, now.year - 1); y <= now.year; y++) {
        buckets.add(_Bucket(SpendPeriod.year(y)));
      }
    } else {
      final n = _range == _ChartRange.months12 ? 12 : 24;
      for (var i = n - 1; i >= 0; i--) {
        final d = DateTime(now.year, now.month - i);
        buckets.add(_Bucket(SpendPeriod.month(d.year, d.month)));
      }
    }
    for (final p in list) {
      for (final b in buckets) {
        if (b.period.contains(p.purchaseDate)) {
          b.total += p.total!;
          b.orders++;
          break;
        }
      }
    }
    return buckets;
  }

  Widget _buildChartCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buckets = _buckets();
    final maxY = buckets.fold<double>(0, (m, b) => math.max(m, b.total));
    final nonZero = buckets.where((b) => b.total > 0).toList();
    final avg = nonZero.isEmpty
        ? 0.0
        : buckets.fold<double>(0, (s, b) => s + b.total) / buckets.length;
    final yStep = maxY <= 0 ? 25.0 : _niceStep(maxY * 1.08 / 4);
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
                    _range == _ChartRange.years
                        ? 'Spend by year'
                        : 'Monthly spend',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                SegmentedButton<_ChartRange>(
                  segments: const [
                    ButtonSegment(
                        value: _ChartRange.months12, label: Text('12 mo')),
                    ButtonSegment(
                        value: _ChartRange.months24, label: Text('24 mo')),
                    ButtonSegment(
                        value: _ChartRange.years, label: Text('Yearly')),
                  ],
                  selected: {_range},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (s) => setState(() => _range = s.first),
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
                          dashArray: [5, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                            labelResolver: (_) =>
                                'avg ${_compactMoney(avg)}',
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
                              _compactMoney(value),
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
                      maxContentWidth: 160,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final b = buckets[group.x];
                        return BarTooltipItem(
                          '${b.period.label}\n',
                          TextStyle(
                            color: scheme.onInverseSurface,
                            fontSize: 11,
                          ),
                          children: [
                            TextSpan(
                              text: _money(b.total),
                              style: TextStyle(
                                color: scheme.onInverseSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '\n${b.orders} order${b.orders == 1 ? '' : 's'}'
                                  '${b.orders > 0 ? ' · tap to filter' : ''}',
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
                      if (b.orders == 0) return;
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
                            toY: buckets[i].total,
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
                  ? 'No $_activeCurrency spend in this range.'
                  : 'Tap a bar to filter the purchase list. Dashed line = average.',
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
    SpendPeriod period,
    SpendPeriod? selected, {
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

  /// Smallest 1/2/2.5/5 × 10ⁿ step ≥ [v], so axis labels read cleanly.
  double _niceStep(double v) {
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in const [1, 2, 2.5, 5, 10]) {
      if (m * exp >= v) return m * exp;
    }
    return 10 * exp;
  }

  // ------------------------------------------------------------ breakdown

  static double _lineAmount(PurchaseItem i) {
    final unit = i.unitCost ?? 0;
    if (i.isTax || i.isShipping) return unit;
    return unit * i.quantity.toDouble();
  }

  Widget _buildBreakdown(BuildContext context) {
    final items = widget.items;
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

    if (items == null) {
      return card(
        'What you buy',
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final byId = {for (final p in widget.purchases) p.id: p};
    final scoped = items.where((i) {
      final p = byId[i.purchaseId];
      if (p == null || p.currency != _activeCurrency) return false;
      return selected == null || selected.contains(p.purchaseDate);
    }).toList();

    // Spend by line type.
    const typeOrder = ['item', 'material', 'misc', 'shipping', 'tax'];
    const typeLabels = {
      'item': 'Tools',
      'material': 'Material',
      'misc': 'Misc',
      'shipping': 'Shipping',
      'tax': 'Tax',
    };
    // Theme secondary/tertiary/outline are near-identical zinc greys, so
    // derive distinguishable swatches from the accent and text colours.
    final typeColors = {
      'item': scheme.primary,
      'material': Color.lerp(scheme.primary, scheme.onSurface, 0.5)!,
      'misc': Color.lerp(scheme.primary, scheme.surface, 0.55)!,
      'shipping': scheme.onSurfaceVariant,
      'tax': Color.lerp(scheme.onSurfaceVariant, scheme.surface, 0.6)!,
    };
    final byType = <String, double>{};
    for (final i in scoped) {
      final t = typeOrder.contains(i.lineType) ? i.lineType : 'misc';
      byType[t] = (byType[t] ?? 0) + _lineAmount(i);
    }
    final typeTotal = byType.values.fold<double>(0, (s, v) => s + v);

    final typeCard = card(
      'Spend by type',
      typeTotal <= 0
          ? _emptyNote(context, 'No line items recorded.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 14,
                    child: Row(
                      children: [
                        for (final t in typeOrder)
                          if ((byType[t] ?? 0) > 0)
                            Expanded(
                              flex: math.max(
                                  1, (byType[t]! / typeTotal * 1000).round()),
                              child: Tooltip(
                                message: typeLabels[t]!,
                                child: Container(color: typeColors[t]),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final t in typeOrder)
                  if ((byType[t] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: typeColors[t],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(typeLabels[t]!)),
                          Text(
                            '${(byType[t]! / typeTotal * 100).toStringAsFixed(0)}%',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 96,
                            child: Text(
                              _money(byType[t]!),
                              textAlign: TextAlign.right,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
    );

    // Top items by spend.
    final groups = <String, _ItemGroup>{};
    for (final i in scoped) {
      if (i.isTax || i.isShipping) continue;
      final p = byId[i.purchaseId]!;
      final key = i.toolId != null
          ? 't:${i.toolId}'
          : i.materialId != null
              ? 'm:${i.materialId}'
              : 'd:${(i.description ?? '').trim().toLowerCase()}';
      final name = i.toolName ??
          i.materialLabel ??
          ((i.description ?? '').trim().isEmpty
              ? 'Misc'
              : i.description!.trim());
      final g = groups.putIfAbsent(key, () => _ItemGroup(name));
      g.spend += _lineAmount(i);
      g.qty += i.quantity.toDouble();
      g.orders.add(p.id);
      if (i.unitCost != null && i.unitCost! > 0) {
        g.prices.add((p.purchaseDate, i.unitCost!));
      }
    }
    final top = groups.values.toList()
      ..sort((a, b) => b.spend.compareTo(a.spend));

    final topCard = card(
      'Top items',
      top.isEmpty
          ? _emptyNote(context, 'No items recorded.')
          : Column(
              children: [
                for (final g in top.take(6)) _topItemRow(context, g),
                if (top.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+ ${top.length - 6} more items',
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
            children: [typeCard, const SizedBox(height: 16), topCard],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: typeCard),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: topCard),
          ],
        );
      },
    );
  }

  Widget _topItemRow(BuildContext context, _ItemGroup g) {
    final scheme = Theme.of(context).colorScheme;
    final qty = g.qty == g.qty.roundToDouble()
        ? g.qty.toStringAsFixed(0)
        : g.qty.toStringAsFixed(2);
    String? priceNote;
    Color? priceColor;
    if (g.prices.length >= 2) {
      g.prices.sort((a, b) => a.$1.compareTo(b.$1));
      final first = g.prices.first.$2;
      final last = g.prices.last.$2;
      final pct = (last - first) / first * 100;
      if (pct.abs() >= 1) {
        priceNote =
            '${pct > 0 ? '+' : '-'}${pct.abs().toStringAsFixed(0)}% unit price';
        priceColor = pct > 0 ? scheme.error : Colors.green.shade700;
      }
    }
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
                  g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text.rich(
                  TextSpan(
                    text:
                        'Qty $qty · ${g.orders.length} order${g.orders.length == 1 ? '' : 's'}',
                    children: [
                      if (g.prices.isNotEmpty)
                        TextSpan(
                          text: ' · last ${_money(g.lastPrice)}',
                        ),
                      if (priceNote != null)
                        TextSpan(
                          text: '  $priceNote',
                          style: TextStyle(
                            color: priceColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _money(g.spend),
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

class _ItemGroup {
  final String name;
  double spend = 0;
  double qty = 0;
  final Set<String> orders = {};
  final List<(DateTime, double)> prices = [];
  _ItemGroup(this.name);

  double get lastPrice {
    var latest = prices.first;
    for (final p in prices) {
      if (p.$1.isAfter(latest.$1)) latest = p;
    }
    return latest.$2;
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final Color? detailColor;
  final bool emphasize;

  const _StatCard({
    required this.label,
    required this.value,
    this.detail,
    this.detailColor,
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
                color: detailColor ??
                    (emphasize
                        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                        : scheme.onSurfaceVariant),
                fontWeight: detailColor != null ? FontWeight.w600 : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
