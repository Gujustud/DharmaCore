import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app_date_field.dart';
import 'auth_service.dart';
import 'list_toolbar_widgets.dart';
import 'maintenance_schedule_utils.dart';
import 'models.dart';
import 'pocketbase_service.dart';

/// Calibration block for Edit Tool (Inspection) — under Inventory, above Price History.
class CalibrationPanel extends StatefulWidget {
  final Tool tool;
  final dynamic schedule; // PocketBase record or null
  final Future<void> Function() onChanged;
  /// Live form values (Edit Tool) — preferred over [tool] for display.
  final String? assetId;
  final String? serialNumber;

  const CalibrationPanel({
    super.key,
    required this.tool,
    required this.schedule,
    required this.onChanged,
    this.assetId,
    this.serialNumber,
  });

  @override
  State<CalibrationPanel> createState() => _CalibrationPanelState();
}

class _CalibrationPanelState extends State<CalibrationPanel> {
  final _pb = PocketBaseService();
  final _nextDueCtrl = TextEditingController();
  final _leadCtrl = TextEditingController(text: '7');

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

  String get _autoName => '${widget.tool.toolName} calibration';

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
    _nextDueCtrl.dispose();
    _leadCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromSchedule() {
    final data = _data;
    final next = parseMaintenanceDate(data['next_due_date']);
    _nextDueCtrl.text = next != null ? formatAppDate(next) : '';
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _history = [];
        _loadingHistory = false;
      });
      _toast('Could not load calibration history: $e', error: true);
    }
  }

  Future<void> _saveNextDue() async {
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
          name: _autoName,
          toolId: widget.tool.id,
          frequencyValue: 12,
          frequencyUnit: 'months',
          nextDueDate: formatAppDateIso(next),
          leadDays: lead,
          active: _active,
          updatedByEmail: AuthService.instance.email,
        );
      } else {
        await _pb.updateCalibrationSchedule(
          id: widget.schedule.id,
          name: _data['name']?.toString().trim().isNotEmpty == true
              ? _data['name'].toString()
              : _autoName,
          toolId: widget.tool.id,
          frequencyValue: 12,
          frequencyUnit: 'months',
          nextDueDate: formatAppDateIso(next),
          lastCompletedDate: _data['last_completed_date']?.toString(),
          leadDays: lead,
          active: _active,
          updatedByEmail: AuthService.instance.email,
        );
      }
      _toast('Next due saved');
      await widget.onChanged();
    } catch (e) {
      _toast('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_CalFormResult?> _showCalibrationForm({
    required String title,
    String? initialDateText,
    String? initialLab,
    String? existingCertName,
    bool showUpdateNextDue = true,
    bool showDelete = false,
  }) async {
    final dateCtrl = TextEditingController(
      text: initialDateText?.trim().isNotEmpty == true
          ? initialDateText!
          : formatAppDate(todayDate()),
    );
    final labCtrl = TextEditingController(text: initialLab ?? '');
    Uint8List? pdfBytes;
    String? pdfName;
    var updateNextDue = showUpdateNextDue;
    var existingLabel = existingCertName;

    final result = await showDialog<Object?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDateField(
                      controller: dateCtrl,
                      initialDate:
                          parseAppDate(dateCtrl.text) ?? todayDate(),
                      labelText: 'Calibration date',
                      allowEmpty: false,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Calibrated at (lab / vendor)',
                        hintText: 'e.g. Wescan',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const [
                            'pdf',
                            'png',
                            'jpg',
                            'jpeg',
                            'webp',
                          ],
                          allowMultiple: false,
                          withData: true,
                        );
                        if (picked == null || picked.files.isEmpty) return;
                        final f = picked.files.first;
                        final bytes = f.bytes;
                        if (bytes == null || bytes.isEmpty) return;
                        setLocal(() {
                          pdfBytes = bytes;
                          pdfName = f.name.trim().isNotEmpty
                              ? f.name.trim()
                              : 'certificate.pdf';
                          existingLabel = pdfName;
                        });
                      },
                      icon: const Icon(Icons.upload_file, size: 20),
                      label: Text(
                        existingLabel == null || existingLabel!.isEmpty
                            ? 'Upload certificate (PDF)'
                            : existingLabel!,
                      ),
                    ),
                    if (showUpdateNextDue)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: updateNextDue,
                        onChanged: (v) =>
                            setLocal(() => updateNextDue = v ?? true),
                        title: const Text(
                          'Set next due to 1 year after this date',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                ),
              ),
              actions: [
                if (showDelete)
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'delete'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'save'),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == 'delete') {
      return const _CalFormResult(delete: true);
    }
    if (result != 'save') return null;

    final completed = parseAppDate(dateCtrl.text);
    if (completed == null) {
      _toast('Invalid calibration date', error: true);
      return null;
    }
    return _CalFormResult(
      completedIso: formatAppDateIso(completed),
      lab: labCtrl.text.trim(),
      updateNextDue: updateNextDue,
      pdfBytes: pdfBytes,
      pdfName: pdfName,
    );
  }

  Future<void> _addCalibration() async {
    final form = await _showCalibrationForm(title: 'Add calibration');
    if (form == null || form.delete) return;

    final completed = parseAppDate(form.completedIso)!;
    final completedIso = form.completedIso!;
    final nextIso = formatAppDateIso(
      advanceMaintenanceDue(
        from: completed,
        frequencyValue: 12,
        frequencyUnit: 'months',
      ),
    );
    final lead = int.tryParse(_leadCtrl.text.trim()) ?? 7;
    final note = form.lab;
    final updateNextDue = form.updateNextDue;

    List<http.MultipartFile>? certFiles;
    if (form.pdfBytes != null && form.pdfBytes!.isNotEmpty) {
      certFiles = [
        http.MultipartFile.fromBytes(
          'certificate',
          form.pdfBytes!,
          filename: form.pdfName ?? 'certificate.pdf',
        ),
      ];
    }

    setState(() => _saving = true);
    try {
      String? scheduleId = widget.schedule?.id?.toString();

      if (scheduleId == null || scheduleId.isEmpty) {
        final seedNext = updateNextDue
            ? nextIso
            : formatAppDateIso(
                advanceMaintenanceDue(
                  from: todayDate(),
                  frequencyValue: 12,
                  frequencyUnit: 'months',
                ),
              );
        final created = await _pb.createCalibrationSchedule(
          name: _autoName,
          toolId: widget.tool.id,
          frequencyValue: 12,
          frequencyUnit: 'months',
          nextDueDate: seedNext,
          leadDays: lead,
          active: _active,
          updatedByEmail: AuthService.instance.email,
        );
        scheduleId = created.id.toString();
        if (updateNextDue) {
          await _pb.updateCalibrationSchedule(
            id: scheduleId,
            name: _autoName,
            toolId: widget.tool.id,
            frequencyValue: 12,
            frequencyUnit: 'months',
            nextDueDate: nextIso,
            lastCompletedDate: completedIso,
            leadDays: lead,
            active: _active,
            updatedByEmail: AuthService.instance.email,
          );
        }
        await _pb.createCalibrationRecord(
          name: _autoName,
          toolId: widget.tool.id,
          completedDate: completedIso,
          note: note,
          updatedByEmail: AuthService.instance.email,
          scheduleId: scheduleId,
          certificateFiles: certFiles,
        );
      } else if (updateNextDue) {
        await _pb.completeCalibrationSchedule(
          scheduleId: scheduleId,
          name: _autoName,
          toolId: widget.tool.id,
          frequencyValue: 12,
          frequencyUnit: 'months',
          completedDate: completedIso,
          note: note,
          leadDays: lead,
          active: _active,
          updatedByEmail: AuthService.instance.email,
          certificateFiles: certFiles,
        );
      } else {
        await _pb.createCalibrationRecord(
          name: _autoName,
          toolId: widget.tool.id,
          completedDate: completedIso,
          note: note,
          updatedByEmail: AuthService.instance.email,
          scheduleId: scheduleId,
          certificateFiles: certFiles,
        );
      }

      _toast('Calibration saved');
      await widget.onChanged();
      if (!mounted) return;
      await _loadHistory();
    } catch (e) {
      _toast('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editCalibration(dynamic record) async {
    final data = Map<String, dynamic>.from(record.data as Map);
    final existingCert = data['certificate']?.toString().trim() ?? '';
    final form = await _showCalibrationForm(
      title: 'Edit calibration',
      initialDateText: formatMaintenanceDateLabel(data['completed_date']),
      initialLab: data['note']?.toString() ?? '',
      existingCertName: existingCert.isNotEmpty ? existingCert : null,
      showUpdateNextDue: false,
      showDelete: true,
    );
    if (form == null) return;

    setState(() => _saving = true);
    try {
      if (form.delete) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete calibration?'),
            content: const Text('This removes the history entry and certificate.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _pb.deleteCalibrationRecord(record.id);
          _toast('Calibration deleted');
          await widget.onChanged();
          if (!mounted) return;
          await _loadHistory();
        }
        return;
      }

      List<http.MultipartFile>? certFiles;
      if (form.pdfBytes != null && form.pdfBytes!.isNotEmpty) {
        certFiles = [
          http.MultipartFile.fromBytes(
            'certificate',
            form.pdfBytes!,
            filename: form.pdfName ?? 'certificate.pdf',
          ),
        ];
      }

      await _pb.updateCalibrationRecord(
        id: record.id,
        name: data['name']?.toString().trim().isNotEmpty == true
            ? data['name'].toString()
            : _autoName,
        toolId: widget.tool.id,
        completedDate: form.completedIso,
        note: form.lab,
        updatedByEmail: AuthService.instance.email,
        scheduleId: data['schedule']?.toString(),
        certificateFiles: certFiles,
      );
      _toast('Calibration updated');
      await widget.onChanged();
      if (!mounted) return;
      await _loadHistory();
    } catch (e) {
      _toast('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openCertificate(dynamic record) async {
    try {
      final data = Map<String, dynamic>.from(record.data as Map);
      final filename = data['certificate']?.toString() ?? '';
      if (filename.isEmpty) {
        _toast('No certificate on file', error: true);
        return;
      }
      final url = _pb.pb.files.getUrl(record, filename);
      final uri = Uri.parse(url.toString());
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) _toast('Could not open certificate', error: true);
    } catch (e) {
      _toast('Error: $e', error: true);
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
    final id = (widget.assetId ?? widget.tool.modelNumber ?? '').trim();
    final serial =
        (widget.serialNumber ?? widget.tool.serialNumber ?? '').trim();

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
        if (id.isNotEmpty || serial.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            [
              if (id.isNotEmpty) 'Model $id',
              if (serial.isNotEmpty) 'S/N $serial',
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        AppDateField(
          controller: _nextDueCtrl,
          labelText: 'Next due',
          allowEmpty: true,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        ),
        const SizedBox(height: 4),
        Text(
          'Usually 1 year after the last calibration.',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Off = paused (no due alerts)'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        InventoryListActionButton(
          label: _saving ? 'Saving…' : 'Save next due',
          icon: Icons.save_outlined,
          onPressed: _saving ? null : _saveNextDue,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: kListToolbarControlHeight,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _saving ? null : _addCalibration,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add calibration'),
          ),
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
        const SizedBox(height: 20),
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
            'No calibrations logged yet. Use Add calibration to enter past or new ones.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          ..._history.take(20).map((r) {
            final d = Map<String, dynamic>.from(r.data as Map);
            final hasCert =
                (d['certificate']?.toString().trim().isNotEmpty ?? false);
            final lab = d['note']?.toString().trim() ?? '';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              onTap: _saving ? null : () => _editCalibration(r),
              title: Text(
                formatMaintenanceDateLabel(d['completed_date']),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: lab.isNotEmpty ? Text(lab) : const Text('Tap to edit'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasCert)
                    IconButton(
                      tooltip: 'Open certificate',
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onPressed: () => _openCertificate(r),
                    ),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: _saving ? null : () => _editCalibration(r),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _CalFormResult {
  final bool delete;
  final String? completedIso;
  final String lab;
  final bool updateNextDue;
  final Uint8List? pdfBytes;
  final String? pdfName;

  const _CalFormResult({
    this.delete = false,
    this.completedIso,
    this.lab = '',
    this.updateNextDue = true,
    this.pdfBytes,
    this.pdfName,
  });
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
