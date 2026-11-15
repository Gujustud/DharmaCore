import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shared shop date helpers + [AppDateField].
///
/// **Policy:** see `docs/APP_DATES.md` and `.cursor/rules/app-dates.mdc`.
/// UI = month/day/year; storage = ISO `yyyy-MM-dd`; typing commits on blur.
///
/// Shared shop date display: month day year, e.g. `Nov 14, 2026`.
final DateFormat appDateDisplayFormat = DateFormat.yMMMd();

/// Format a date for UI fields and lists (month/day/year).
String formatAppDate(DateTime d) => appDateDisplayFormat.format(d);

/// ISO date-only for PocketBase / APIs (`yyyy-MM-dd`).
String formatAppDateIso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Parse flexible user / stored date text into a calendar date.
///
/// Accepts:
/// - `Nov 14, 2026` (and similar [DateFormat.yMMMd] output)
/// - `M/d/yyyy`, `MM/dd/yyyy`
/// - `M-d-yyyy`, `MM-dd-yyyy`
/// - `yyyy-MM-dd`, `yyyy-M-d`
/// - ISO datetime strings
DateTime? parseAppDate(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;

  DateTime? tryFmt(String pattern) {
    try {
      final d = DateFormat(pattern).parseStrict(t);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  return tryFmt('yyyy-MM-dd') ??
      tryFmt('yyyy-M-d') ??
      tryFmt('M/d/yyyy') ??
      tryFmt('MM/dd/yyyy') ??
      tryFmt('M-d-yyyy') ??
      tryFmt('MM-dd-yyyy') ??
      (() {
        try {
          return appDateDisplayFormat.parse(t);
        } catch (_) {
          return null;
        }
      })() ??
      (() {
        try {
          final d = DateTime.parse(t);
          return DateTime(d.year, d.month, d.day);
        } catch (_) {
          return null;
        }
      })();
}

/// Display string for a stored value (ISO or already friendly). Empty → `''`.
String formatAppDateText(String? raw) {
  final d = parseAppDate(raw);
  if (d == null) return (raw ?? '').trim();
  return formatAppDate(d);
}

/// Typeable date field + calendar. Parses on blur (leave field) and Enter.
///
/// Shows [formatAppDate]; use [onDateChanged] / read via [controller] after blur.
class AppDateField extends StatefulWidget {
  final TextEditingController? controller;
  final DateTime? initialDate;
  final String? labelText;
  final String? hintText;
  final bool enabled;
  final bool isDense;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime?>? onDateChanged;
  final InputDecoration? decoration;
  final bool allowEmpty;

  const AppDateField({
    super.key,
    this.controller,
    this.initialDate,
    this.labelText,
    this.hintText,
    this.enabled = true,
    this.isDense = false,
    this.firstDate,
    this.lastDate,
    this.onDateChanged,
    this.decoration,
    this.allowEmpty = true,
  });

  @override
  State<AppDateField> createState() => _AppDateFieldState();
}

class _AppDateFieldState extends State<AppDateField> {
  late final TextEditingController _ctrl;
  late final bool _ownsController;
  final FocusNode _focus = FocusNode();

  DateTime get _first => widget.firstDate ?? DateTime(2017);
  DateTime get _last =>
      widget.lastDate ?? DateTime.now().add(const Duration(days: 365 * 20));

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ctrl = widget.controller ?? TextEditingController();
    if (_ownsController) {
      final d = widget.initialDate;
      if (d != null) _ctrl.text = formatAppDate(d);
    } else if (_ctrl.text.trim().isNotEmpty) {
      final d = parseAppDate(_ctrl.text);
      if (d != null) _ctrl.text = formatAppDate(d);
    }
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      // External controller swap is uncommon; keep current _ctrl.
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    if (_ownsController) _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) {
      if (widget.allowEmpty) {
        if (_ctrl.text.isNotEmpty) _ctrl.text = '';
        widget.onDateChanged?.call(null);
      } else if (widget.initialDate != null) {
        _ctrl.text = formatAppDate(widget.initialDate!);
      }
      return;
    }
    final d = parseAppDate(t);
    if (d == null) {
      // Revert to last good value from controller if it was ISO/friendly.
      final prev = parseAppDate(_ctrl.text);
      if (prev != null) {
        _ctrl.text = formatAppDate(prev);
      } else if (widget.initialDate != null) {
        _ctrl.text = formatAppDate(widget.initialDate!);
      }
      return;
    }
    final pretty = formatAppDate(d);
    if (_ctrl.text != pretty) _ctrl.text = pretty;
    widget.onDateChanged?.call(d);
  }

  Future<void> _pick() async {
    if (!widget.enabled) return;
    var initial = parseAppDate(_ctrl.text) ?? widget.initialDate ?? DateTime.now();
    if (initial.isBefore(_first)) initial = _first;
    if (initial.isAfter(_last)) initial = _last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _first,
      lastDate: _last,
    );
    if (picked == null || !mounted) return;
    _ctrl.text = formatAppDate(picked);
    widget.onDateChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.decoration ??
        InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText ?? 'Nov 14, 2026 or 11/14/2026',
          border: const OutlineInputBorder(),
          isDense: widget.isDense,
          floatingLabelBehavior: widget.labelText != null
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
        );
    final deco = base.copyWith(
      suffixIcon: IconButton(
        icon: const Icon(Icons.calendar_today),
        tooltip: 'Pick date',
        onPressed: widget.enabled ? _pick : null,
      ),
    );

    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: TextInputType.datetime,
      decoration: deco,
      onEditingComplete: () {
        _commit();
        _focus.unfocus();
      },
      onSubmitted: (_) {
        _commit();
        _focus.unfocus();
      },
      onTapOutside: (_) {
        _commit();
        _focus.unfocus();
      },
    );
  }
}
