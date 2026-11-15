import 'package:flutter/material.dart';

import 'app_date_field.dart';
import 'auth_service.dart';
import 'list_toolbar_widgets.dart';
import 'maintenance_schedule_utils.dart';
import 'models.dart';
import 'pocketbase_service.dart';

/// Calibration schedule + history for an Inspection tool.
/// Designed to embed in Edit Tool (right column under Inventory), not as a page panel.
class CalibrationPanel extends StatefulWidget {
  final Tool tool;
  final dynamic schedule; // PocketBase record or null
  final VoidCallback onChanged;

  const CalibrationPanel({
    super.key,
    required this.tool,
    required this.schedule,
    required this.onChanged,
  });

  @override
  State<CalibrationPanel> createState() => _CalibrationPanelState();
}

class _CalibrationPanelState extends State<CalibrationPanel> {
  final _pb = PocketBaseService();
  final _nameCtrl = TextEditingController();
  final _freqCtrl = TextEditingController(text: '12');
  final _nextDueCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _leadCtrl = TextEditingController(text: '7');

  String _freqUnit = 'months';
  bool _active = true;
  bool _saving = false;
  bool _loadingHistory = true;
  List<dynamic> _history = [];

  Map<String, dynamic> get _data {
    final s = widget.schedule;
    if (s == null) return {};
    try {
      return Map<String, dynamic>.from(s.data as Map);
    } catch (_) {
      return {};
    }
  }

  @override
  void initState() {
    super.initState();
    _hydrateFromSchedule();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant CalibrationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tool.id != widget.tool.id ||
        oldWidget.schedule?.id != widget.schedule?.id) {
      _hydrateFromSchedule();
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _freqCtrl.dispose();
    _nextDueCtrl.dispose();
    _noteCtrl.dispose();
    _leadCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromSchedule() {
    final data = _data;
    final defaultName = '${widget.tool.toolName} calibration';
    _nameCtrl.text = (data['name']?.toString().trim().isNotEmpty == true)
        ? data['name'].toString()
        : defaultName;
    final freq = data['frequency_value'];
    _freqCtrl.text = freq != null
        ? '${freq is num ? freq.toInt() : int.tryParse('$freq') ?? 12}'
        : '12';
    _freqUnit = '${data['frequency_unit'] ?? 'months'}';
    if (_freqUnit != 'days' && _freqUnit != 'weeks' && _freqUnit != 'months') {
      _freqUnit = 'months';
    }
    final next = parseMaintenanceDate(data['next_due_date']);
    _nextDueCtrl.text = next != null ? formatAppDate(next) : '';
    _noteCtrl.text = data['note']?.toString() ?? '';
    _leadCtrl.text = '${leadDaysOf(data)}';
    _active = scheduleIsActive(data);
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final rows = await _pb.getCalibrationRecordsForTool(widget.tool.id);
      if (!mounted) return;
      setState(() {
        _history = rows;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _history = [];
        _loadingHistory = false;
      });
    }
  }

  Future<void> _saveSchedule() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('Name is required', error: true);
      return;
    }
    final freq = int.tryParse(_freqCtrl.text.trim()) ?? 0;
    if (freq < 1) {
      _toast('Frequency must be at least 1', error: true);
      return;
    }
    final next = parseAppDate(_nextDueCtrl.text);
    if (next == null) {
      _toast('Next due date is required', error: true);
      return;
    }
    final lead = int.tryParse(_leadCtrl.text.trim()) ?? 7;

    setState(() => _saving = true);
    try {
      if (widget.schedule == null) {
        await _pb.createCalibrationSchedule(
          name: name,
          toolId: widget.tool.id,
          frequencyValue: freq,
          frequencyUnit: _freqUnit,
          nextDueDate: formatAppDateIso(next),
          note: _noteCtrl.text.trim(),
          leadDays: lead,
          active: _active,
          updatedByEmail: AuthService.instance.email,
        );
      } else {
        await _pb.updateCalibrationSchedule(
          id: widget.schedule.id,
          name: name,
          toolId: widget.tool.id,
          frequencyValue: freq,
          frequencyUnit: _freqUnit,
          nextDueDate: formatAppDateIso(next),
          lastCompletedDate: _data['last_completed_date']?.toString(),
          note: _noteCtrl.text.trim(),
          leadDays: lead,
          active: _active,
          updatedByEmail: AuthService.instance.email,
        );
      }
      _toast('Calibration schedule saved');
      widget.onChanged();
    } catch (e) {
      _toast('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markCalibrated() async {
    if (widget.schedule == null) {
      _toast('Save a schedule first', error: true);
      return;
    }
    final dateCtrl = TextEditingController(text: formatAppDate(todayDate()));
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark calibrated'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDateField(
                controller: dateCtrl,
                initialDate: todayDate(),
                labelText: 'Completed date',
                allowEmpty: false,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. Wescan cert on file',
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark calibrated'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final completed = parseAppDate(dateCtrl.text);
    if (completed == null) {
      _toast('Invalid completed date', error: true);
      return;
    }

    final freq = _data['frequency_value'];
    final freqValue =
        freq is num ? freq.toInt() : int.tryParse('$freq') ?? 1;
    final unit = '${_data['frequency_unit'] ?? _freqUnit}';

    setState(() => _saving = true);
    try {
      await _pb.completeCalibrationSchedule(
        scheduleId: widget.schedule.id,
        name: _nameCtrl.text.trim().isEmpty
            ? '${widget.tool.toolName} calibration'
            : _nameCtrl.text.trim(),
        toolId: widget.tool.id,
        frequencyValue: freqValue,
        frequencyUnit: unit,
        completedDate: formatAppDateIso(completed),
        note: noteCtrl.text.trim(),
        leadDays: leadDaysOf(_data),
        active: scheduleIsActive(_data),
        updatedByEmail: AuthService.instance.email,
      );
      _toast('Logged and next due updated');
      widget.onChanged();
      await _loadHistory();
    } catch (e) {
      _toast('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = widget.schedule == null ? null : dueStatusOf(_data);
    final serial = (widget.tool.serialNumber ?? '').trim();

    // Shrink-wrap Column so this can sit inside Edit Tool's right ListView.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Calibration',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (status != null) _DueChip(status: status),
          ],
        ),
        if (serial.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'S/N $serial',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Schedule name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _freqCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Every',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: _freqUnit,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'days', child: Text('days')),
                  DropdownMenuItem(value: 'weeks', child: Text('weeks')),
                  DropdownMenuItem(value: 'months', child: Text('months')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _freqUnit = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppDateField(
          controller: _nextDueCtrl,
          labelText: 'Next due',
          allowEmpty: false,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _leadCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Lead days (due soon)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note',
            border: OutlineInputBorder(),
            hintText: 'Vendor, tolerance, etc.',
          ),
          minLines: 2,
          maxLines: 4,
        ),
        if (widget.schedule != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last calibrated: ${formatMaintenanceDateLabel(_data['last_completed_date'])}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        InventoryListActionButton(
          label: _saving
              ? 'Saving…'
              : (widget.schedule == null
                  ? 'Create schedule'
                  : 'Save schedule'),
          icon: Icons.save_outlined,
          onPressed: _saving ? null : _saveSchedule,
        ),
        if (widget.schedule != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: kListToolbarControlHeight,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _markCalibrated,
              icon: const Icon(Icons.verified_outlined, size: 20),
              label: const Text('Mark calibrated'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'History',
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingHistory)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_history.isEmpty)
          Text(
            'No calibration records yet.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          ..._history.take(12).map((r) {
            final d = Map<String, dynamic>.from(r.data as Map);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                formatMaintenanceDateLabel(d['completed_date']),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: (d['note']?.toString().trim().isNotEmpty == true)
                  ? Text(d['note'].toString())
                  : null,
            );
          }),
      ],
    );
  }
}

class _DueChip extends StatelessWidget {
  final MaintenanceDueStatus status;

  const _DueChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (status) {
      MaintenanceDueStatus.overdue => (
          'Overdue',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      MaintenanceDueStatus.dueSoon => (
          'Due soon',
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      MaintenanceDueStatus.inactive => (
          'Paused',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      MaintenanceDueStatus.ok => (
          'OK',
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Small status pill for Inspection list rows.
class CalibrationDueBadge extends StatelessWidget {
  final MaintenanceDueStatus status;

  const CalibrationDueBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == MaintenanceDueStatus.ok ||
        status == MaintenanceDueStatus.inactive) {
      return const SizedBox.shrink();
    }
    return _DueChip(status: status);
  }
}
