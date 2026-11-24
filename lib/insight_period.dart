import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// A calendar month (`month` set) or whole year (`month` null) for insight charts.
@immutable
class InsightPeriod {
  final int year;
  final int? month;

  const InsightPeriod.year(this.year) : month = null;
  const InsightPeriod.month(this.year, int this.month);

  bool contains(DateTime d) =>
      d.year == year && (month == null || d.month == month);

  String get label => month == null
      ? '$year'
      : DateFormat.yMMM().format(DateTime(year, month!));

  @override
  bool operator ==(Object other) =>
      other is InsightPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}
