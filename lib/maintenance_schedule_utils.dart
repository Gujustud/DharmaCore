import 'app_date_field.dart';

/// Due status for a maintenance schedule (in-app alerts).
enum MaintenanceDueStatus { overdue, dueSoon, ok, inactive }

DateTime? parseMaintenanceDate(dynamic raw) {
  if (raw == null) return null;
  return parseAppDate(raw.toString());
}

/// ISO for PocketBase writes (`yyyy-MM-dd`).
String formatMaintenanceDate(DateTime d) => formatAppDateIso(d);

/// UI / list label (`Nov 14, 2026`).
String formatMaintenanceDateLabel(dynamic raw) {
  final d = parseMaintenanceDate(raw);
  if (d == null) return '—';
  return formatAppDate(d);
}

DateTime todayDate() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Advance [from] by frequency (days / weeks / months).
DateTime advanceMaintenanceDue({
  required DateTime from,
  required int frequencyValue,
  required String frequencyUnit,
}) {
  final n = frequencyValue < 1 ? 1 : frequencyValue;
  switch (frequencyUnit) {
    case 'weeks':
      return from.add(Duration(days: 7 * n));
    case 'months':
      final month = from.month - 1 + n;
      final year = from.year + month ~/ 12;
      final monthNorm = month % 12 + 1;
      final day = from.day.clamp(1, _daysInMonth(year, monthNorm));
      return DateTime(year, monthNorm, day);
    case 'days':
    default:
      return from.add(Duration(days: n));
  }
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

int leadDaysOf(Map<String, dynamic> data, {int fallback = 7}) {
  final v = data['lead_days'];
  if (v is num) return v.toInt().clamp(0, 3650);
  return int.tryParse('$v')?.clamp(0, 3650) ?? fallback;
}

bool scheduleIsActive(Map<String, dynamic> data) {
  final v = data['active'];
  // Default true when unset (new schedules set active: true on create).
  if (v == null) return true;
  return v == true || v == 1 || v == 'true';
}

MaintenanceDueStatus dueStatusOf(
  Map<String, dynamic> data, {
  DateTime? today,
}) {
  if (!scheduleIsActive(data)) return MaintenanceDueStatus.inactive;
  final due = parseMaintenanceDate(data['next_due_date']);
  if (due == null) return MaintenanceDueStatus.ok;
  final t = today ?? todayDate();
  if (due.isBefore(t)) return MaintenanceDueStatus.overdue;
  final lead = leadDaysOf(data);
  final soonEnd = t.add(Duration(days: lead));
  if (!due.isAfter(soonEnd)) return MaintenanceDueStatus.dueSoon;
  return MaintenanceDueStatus.ok;
}

String frequencyLabel(Map<String, dynamic> data) {
  final n = data['frequency_value'];
  final unit = '${data['frequency_unit'] ?? 'days'}';
  final value = n is num ? n.toInt() : int.tryParse('$n') ?? 1;
  final unitLabel = switch (unit) {
    'weeks' => value == 1 ? 'week' : 'weeks',
    'months' => value == 1 ? 'month' : 'months',
    _ => value == 1 ? 'day' : 'days',
  };
  return 'Every $value $unitLabel';
}

String dueStatusLabel(MaintenanceDueStatus s) {
  switch (s) {
    case MaintenanceDueStatus.overdue:
      return 'Overdue';
    case MaintenanceDueStatus.dueSoon:
      return 'Due soon';
    case MaintenanceDueStatus.inactive:
      return 'Paused';
    case MaintenanceDueStatus.ok:
      return 'OK';
  }
}
