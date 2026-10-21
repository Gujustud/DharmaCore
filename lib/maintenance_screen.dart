import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'drawer_behavior.dart';
import 'list_toolbar_widgets.dart';
import 'maintenance_schedule_utils.dart';
import 'part_images_panel.dart';
import 'pocketbase_service.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';

class _PendingPhoto {
  final String name;
  final Uint8List bytes;

  const _PendingPhoto({required this.name, required this.bytes});
}

List<http.MultipartFile> _pendingPhotoMultipart(List<_PendingPhoto> photos) {
  return [
    for (final p in photos)
      http.MultipartFile.fromBytes('photos', p.bytes, filename: p.name),
  ];
}

Future<void> _pickPendingPhotos({
  required List<_PendingPhoto> current,
  required void Function(List<_PendingPhoto>) onChanged,
  int maxFiles = 8,
}) async {
  if (current.length >= maxFiles) return;
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    allowMultiple: true,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return;
  final next = List<_PendingPhoto>.from(current);
  for (final file in result.files) {
    if (next.length >= maxFiles) break;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) continue;
    final name = (file.name.trim().isNotEmpty)
        ? file.name.trim()
        : 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg';
    next.add(_PendingPhoto(name: name, bytes: bytes));
  }
  onChanged(next);
}

Widget _buildPendingPhotosSection({
  required List<_PendingPhoto> photos,
  required void Function(List<_PendingPhoto>) onChanged,
  int maxFiles = 8,
}) {
  final canAdd = photos.length < maxFiles;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Photos',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (photos.isEmpty)
        InkWell(
          onTap: () => _pickPendingPhotos(
            current: photos,
            onChanged: onChanged,
            maxFiles: maxFiles,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Click to add photos\n(Max $maxFiles)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        )
      else
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length + (canAdd ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (canAdd && index == photos.length) {
                return InkWell(
                  onTap: () => _pickPendingPhotos(
                    current: photos,
                    onChanged: onChanged,
                    maxFiles: maxFiles,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 96,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Colors.grey[600]),
                        Text(
                          'Add',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final photo = photos[index];
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      photo.bytes,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Material(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        onTap: () {
                          final next = List<_PendingPhoto>.from(photos)
                            ..removeAt(index);
                          onChanged(next);
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
    ],
  );
}

/// Shop maintenance: completion log + recurring schedules with due alerts.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen>
    with AutoOpenDrawerMixin {
  static const _tabLog = 0;
  static const _tabSchedule = 1;

  List<dynamic> _machines = [];
  List<dynamic> _records = [];
  List<dynamic> _schedules = [];
  List<dynamic> _filteredRecords = [];
  List<dynamic> _filteredSchedules = [];
  bool _isLoading = true;
  int _tab = _tabLog;
  String? _machineFilterId;
  final _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final pb = PocketBaseService();
      final machines = await pb.getMaintenanceMachines();
      final records = await pb.getMaintenanceRecords();
      List<dynamic> schedules = [];
      try {
        schedules = await pb.getMaintenanceSchedules();
      } catch (_) {
        // Collection may not exist until migration is applied.
        schedules = [];
      }
      if (!mounted) return;
      setState(() {
        _machines = machines;
        _records = records;
        _schedules = schedules;
        _filteredRecords = _applyRecordFilters(records);
        _filteredSchedules = _applyScheduleFilters(schedules);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading maintenance: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Map<String, dynamic> _data(dynamic record) {
    if (record is Map<String, dynamic>) return record;
    try {
      return Map<String, dynamic>.from(record.data as Map);
    } catch (_) {
      return {};
    }
  }

  String _machineIdOf(dynamic record) {
    final v = _data(record)['machine'];
    if (v == null) return '';
    return v.toString();
  }

  String _machineNameOf(dynamic record) {
    try {
      final expand = record.expand as Map?;
      final m = expand?['machine'];
      if (m is List && m.isNotEmpty) {
        return '${m.first.data['name'] ?? ''}'.trim();
      }
      if (m != null && m.data != null) {
        return '${m.data['name'] ?? ''}'.trim();
      }
    } catch (_) {}
    final id = _machineIdOf(record);
    for (final m in _machines) {
      if (m.id == id) return '${_data(m)['name'] ?? ''}'.trim();
    }
    return id;
  }

  List<dynamic> _applyRecordFilters(List<dynamic> source) {
    final q = _searchController.text.trim().toLowerCase();
    return source.where((r) {
      final data = _data(r);
      if (_machineFilterId != null && _machineIdOf(r) != _machineFilterId) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        data['name'],
        data['note'],
        _machineNameOf(r),
        data['completed_date'],
      ].map((v) => '${v ?? ''}'.toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  List<dynamic> _applyScheduleFilters(List<dynamic> source) {
    final q = _searchController.text.trim().toLowerCase();
    final list = source.where((r) {
      final data = _data(r);
      if (_machineFilterId != null && _machineIdOf(r) != _machineFilterId) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        data['name'],
        data['note'],
        _machineNameOf(r),
        data['next_due_date'],
        frequencyLabel(data),
      ].map((v) => '${v ?? ''}'.toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();

    list.sort((a, b) {
      final sa = dueStatusOf(_data(a));
      final sb = dueStatusOf(_data(b));
      final rank = (MaintenanceDueStatus s) {
        switch (s) {
          case MaintenanceDueStatus.overdue:
            return 0;
          case MaintenanceDueStatus.dueSoon:
            return 1;
          case MaintenanceDueStatus.ok:
            return 2;
          case MaintenanceDueStatus.inactive:
            return 3;
        }
      };
      final c = rank(sa).compareTo(rank(sb));
      if (c != 0) return c;
      final da = parseMaintenanceDate(_data(a)['next_due_date']);
      final db = parseMaintenanceDate(_data(b)['next_due_date']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return list;
  }

  void _refilter() {
    setState(() {
      _filteredRecords = _applyRecordFilters(_records);
      _filteredSchedules = _applyScheduleFilters(_schedules);
    });
  }

  int get _overdueCount => _schedules
      .where((s) => dueStatusOf(_data(s)) == MaintenanceDueStatus.overdue)
      .length;

  int get _dueSoonCount => _schedules
      .where((s) => dueStatusOf(_data(s)) == MaintenanceDueStatus.dueSoon)
      .length;

  Future<void> _openRecordEditor({dynamic record}) async {
    if (_machines.isEmpty) {
      final added = await _promptAddMachine();
      if (added != true) return;
      await _loadData();
      if (!mounted || _machines.isEmpty) return;
    }
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _MaintenanceRecordDialog(
        record: record,
        machines: _machines,
        onAddMachine: _promptAddMachine,
      ),
    );
    if (changed == true) _loadData();
  }

  Future<void> _openScheduleEditor({dynamic schedule}) async {
    if (_machines.isEmpty) {
      final added = await _promptAddMachine();
      if (added != true) return;
      await _loadData();
      if (!mounted || _machines.isEmpty) return;
    }
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _MaintenanceScheduleDialog(
        schedule: schedule,
        machines: _machines,
        onAddMachine: _promptAddMachine,
      ),
    );
    if (changed == true) _loadData();
  }

  Future<void> _markScheduleDone(dynamic schedule) async {
    final data = _data(schedule);
    final dateCtrl = TextEditingController(text: formatMaintenanceDate(todayDate()));
    final noteCtrl = TextEditingController();
    var pendingPhotos = <_PendingPhoto>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Mark done: ${data['name'] ?? ''}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: dateCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Completed date',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today_outlined),
                        onPressed: () async {
                          var initial = todayDate();
                          try {
                            initial = DateTime.parse(dateCtrl.text);
                          } catch (_) {}
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            dateCtrl.text = formatMaintenanceDate(picked);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Note (optional)'),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  _buildPendingPhotosSection(
                    photos: pendingPhotos,
                    onChanged: (next) => setLocal(() => pendingPhotos = next),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mark done'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final freq = data['frequency_value'];
    final freqValue = freq is num ? freq.toInt() : int.tryParse('$freq') ?? 1;
    final unit = '${data['frequency_unit'] ?? 'days'}';
    try {
      await PocketBaseService().completeMaintenanceSchedule(
        scheduleId: schedule.id,
        name: '${data['name'] ?? ''}'.trim(),
        machineId: _machineIdOf(schedule),
        frequencyValue: freqValue,
        frequencyUnit: unit,
        completedDate: dateCtrl.text.trim(),
        note: noteCtrl.text,
        leadDays: leadDaysOf(data),
        active: scheduleIsActive(data),
        updatedByEmail: AuthService.instance.email,
        photoFiles: pendingPhotos.isEmpty
            ? null
            : _pendingPhotoMultipart(pendingPhotos),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logged and next due updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<bool?> _promptAddMachine() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add machine'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Machine name',
            hintText: 'e.g. DMU65',
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return false;
    try {
      final nextOrder = _machines.isEmpty
          ? 10
          : ((_machines
                      .map((m) => (_data(m)['sort_order'] as num?)?.toInt() ?? 0)
                      .fold<int>(0, (a, b) => a > b ? a : b)) +
                  10);
      await PocketBaseService().createMaintenanceMachine(
        name: name,
        sortOrder: nextOrder,
      );
      await _loadData();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  Future<void> _manageMachines() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ManageMachinesDialog(
        machines: List<dynamic>.from(_machines),
        onChanged: _loadData,
      ),
    );
    await _loadData();
  }

  Future<void> _deleteRecord(dynamic record) async {
    final label = '${_data(record)['name'] ?? 'this record'}'.trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete record'),
        content: Text('Delete "$label"?'),
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
    if (confirm != true) return;
    try {
      await PocketBaseService().deleteMaintenanceRecord(record.id);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSchedule(dynamic schedule) async {
    final label = '${_data(schedule)['name'] ?? 'this schedule'}'.trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete schedule'),
        content: Text('Delete "$label"? Past log rows are kept.'),
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
    if (confirm != true) return;
    try {
      await PocketBaseService().deleteMaintenanceSchedule(schedule.id);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _statusColor(MaintenanceDueStatus s, ColorScheme scheme) {
    switch (s) {
      case MaintenanceDueStatus.overdue:
        return scheme.error;
      case MaintenanceDueStatus.dueSoon:
        return scheme.tertiary;
      case MaintenanceDueStatus.inactive:
        return scheme.outline;
      case MaintenanceDueStatus.ok:
        return scheme.primary;
    }
  }

  static const double _wideBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    maybeAutoOpenDrawer();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= _wideBreakpoint;
    final scheme = Theme.of(context).colorScheme;
    final showAlert = _overdueCount > 0 || _dueSoonCount > 0;

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Maintenance'),
        backgroundColor: scheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : workspaceContentFrame(
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showAlert) ...[
                        _buildAlertBanner(scheme, isWide: isWide),
                        const SizedBox(height: 12),
                      ],
                      if (!isWide) ...[
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(
                              value: _tabLog,
                              label: Text('Log'),
                              icon: Icon(Icons.history, size: 18),
                            ),
                            ButtonSegment(
                              value: _tabSchedule,
                              label: Text('Schedule'),
                              icon: Icon(Icons.event_repeat, size: 18),
                            ),
                          ],
                          selected: {_tab},
                          onSelectionChanged: (s) {
                            setState(() {
                              _tab = s.first;
                              _refilter();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      InventoryListSearchField(
                        controller: _searchController,
                        hintText: 'Search name, note, machine…',
                        onChanged: (_) => _refilter(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('All machines'),
                            selected: _machineFilterId == null,
                            onSelected: (_) {
                              setState(() {
                                _machineFilterId = null;
                                _refilter();
                              });
                            },
                          ),
                          ..._machines.map((m) {
                            final id = m.id as String;
                            final name = '${_data(m)['name'] ?? ''}'.trim();
                            return FilterChip(
                              label: Text(name),
                              selected: _machineFilterId == id,
                              onSelected: (_) {
                                setState(() {
                                  _machineFilterId =
                                      _machineFilterId == id ? null : id;
                                  _refilter();
                                });
                              },
                            );
                          }),
                          IconButton(
                            tooltip: 'Manage machines',
                            onPressed: _manageMachines,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildPane(
                                      scheme: scheme,
                                      title: 'Schedule',
                                      actionLabel: 'Add schedule',
                                      onAdd: () => _openScheduleEditor(),
                                      child: _buildScheduleList(
                                        scheme,
                                        compact: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildPane(
                                      scheme: scheme,
                                      title: 'Log',
                                      actionLabel: 'Add record',
                                      onAdd: () => _openRecordEditor(),
                                      child: _buildLogList(
                                        scheme,
                                        compact: true,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: InventoryListActionButton(
                                      label: _tab == _tabLog
                                          ? 'Add record'
                                          : 'Add schedule',
                                      icon: Icons.add,
                                      onPressed: () => _tab == _tabLog
                                          ? _openRecordEditor()
                                          : _openScheduleEditor(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: _tab == _tabLog
                                        ? _buildLogList(
                                            scheme,
                                            compact: false,
                                          )
                                        : _buildScheduleList(
                                            scheme,
                                            compact: false,
                                          ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
            ),
    );
  }

  Widget _buildAlertBanner(ColorScheme scheme, {required bool isWide}) {
    final overdue = _overdueCount > 0;
    return Material(
      color: overdue ? scheme.errorContainer : scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isWide
            ? null
            : () {
                setState(() {
                  _tab = _tabSchedule;
                  _refilter();
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: overdue
                    ? scheme.onErrorContainer
                    : scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  [
                    if (_overdueCount > 0) '$_overdueCount overdue',
                    if (_dueSoonCount > 0) '$_dueSoonCount due soon',
                  ].join(' · '),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: overdue
                        ? scheme.onErrorContainer
                        : scheme.onTertiaryContainer,
                  ),
                ),
              ),
              if (!isWide)
                Text(
                  'View schedules',
                  style: TextStyle(
                    color: overdue
                        ? scheme.onErrorContainer
                        : scheme.onTertiaryContainer,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPane({
    required ColorScheme scheme,
    required String title,
    required String actionLabel,
    required VoidCallback onAdd,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(actionLabel),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildLogList(ColorScheme scheme, {required bool compact}) {
    if (_filteredRecords.isEmpty) {
      return Center(
        child: Text(
          _records.isEmpty
              ? 'No maintenance records yet.\nAdd ad-hoc work here, or Mark done on a schedule.'
              : 'No records match this filter.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _filteredRecords.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final record = _filteredRecords[index];
        final data = _data(record);
        final name = '${data['name'] ?? ''}'.trim().isEmpty
            ? '(untitled)'
            : '${data['name']}'.trim();
        final date = formatMaintenanceDateLabel(data['completed_date']);
        final machine = _machineNameOf(record);
        final note = '${data['note'] ?? ''}'.trim();
        final photoCount =
            PartImagesPanel.normalizeFilenames(data['photos']).length;
        return Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openRecordEditor(record: record),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            date,
                            if (machine.isNotEmpty) machine,
                            if (photoCount > 0)
                              '$photoCount photo${photoCount == 1 ? '' : 's'}',
                          ].join(' · '),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            note,
                            maxLines: compact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (photoCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 4, top: 2),
                      child: Icon(
                        Icons.photo_library_outlined,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') {
                        _openRecordEditor(record: record);
                      } else if (v == 'delete') {
                        _deleteRecord(record);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScheduleList(ColorScheme scheme, {required bool compact}) {
    if (_filteredSchedules.isEmpty) {
      return Center(
        child: Text(
          _schedules.isEmpty
              ? 'No schedules yet.\nAdd one (e.g. grease every 30 days), then Mark done when finished.'
              : 'No schedules match this filter.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _filteredSchedules.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final schedule = _filteredSchedules[index];
        final data = _data(schedule);
        final name = '${data['name'] ?? ''}'.trim().isEmpty
            ? '(untitled)'
            : '${data['name']}'.trim();
        final status = dueStatusOf(data);
        final machine = _machineNameOf(schedule);
        final note = '${data['note'] ?? ''}'.trim();
        final statusColor = _statusColor(status, scheme);

        return Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: status == MaintenanceDueStatus.overdue ||
                      status == MaintenanceDueStatus.dueSoon
                  ? statusColor.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openScheduleEditor(schedule: schedule),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: statusColor),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dueStatusLabel(status),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') {
                            _openScheduleEditor(schedule: schedule);
                          } else if (v == 'done') {
                            _markScheduleDone(schedule);
                          } else if (v == 'delete') {
                            _deleteSchedule(schedule);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          if (scheduleIsActive(data))
                            const PopupMenuItem(
                              value: 'done',
                              child: Text('Mark done'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      machine.isEmpty ? '—' : machine,
                      frequencyLabel(data),
                      'Next ${formatMaintenanceDateLabel(data['next_due_date'])}',
                    ].join(' · '),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (scheduleIsActive(data)) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _markScheduleDone(schedule),
                        child: const Text('Mark done'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MaintenanceRecordDialog extends StatefulWidget {
  final dynamic record;
  final List<dynamic> machines;
  final Future<bool?> Function() onAddMachine;

  const _MaintenanceRecordDialog({
    this.record,
    required this.machines,
    required this.onAddMachine,
  });

  @override
  State<_MaintenanceRecordDialog> createState() =>
      _MaintenanceRecordDialogState();
}

class _MaintenanceRecordDialogState extends State<_MaintenanceRecordDialog> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _date;
  String? _machineId;
  bool _saving = false;
  List<dynamic> _machines = [];
  List<String> _photoFilenames = [];
  List<_PendingPhoto> _pendingPhotos = [];
  bool _photosDirty = false;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    _machines = List<dynamic>.from(widget.machines);
    final data = widget.record == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(widget.record.data as Map);
    _name = TextEditingController(text: '${data['name'] ?? ''}');
    _note = TextEditingController(text: '${data['note'] ?? ''}');
    final rawDate = '${data['completed_date'] ?? ''}'.trim();
    _date = TextEditingController(
      text: rawDate.length >= 10
          ? rawDate.substring(0, 10)
          : (rawDate.isEmpty ? formatMaintenanceDate(todayDate()) : rawDate),
    );
    final mid = data['machine']?.toString();
    _machineId = (mid != null && mid.isNotEmpty)
        ? mid
        : (_machines.isNotEmpty ? _machines.first.id as String : null);
    _photoFilenames = PartImagesPanel.normalizeFilenames(data['photos']);
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    var initial = DateTime.now();
    final t = _date.text.trim();
    if (t.isNotEmpty) {
      try {
        initial = DateTime.parse(t);
      } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _date.text = formatMaintenanceDate(picked));
  }

  Future<void> _addMachineInline() async {
    final ok = await widget.onAddMachine();
    if (ok == true && mounted) {
      final machines = await PocketBaseService().getMaintenanceMachines();
      setState(() {
        _machines = machines;
        _machineId ??= machines.isNotEmpty ? machines.first.id as String : null;
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _machineId == null || _machineId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name and machine are required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final email = AuthService.instance.email;
    try {
      final pb = PocketBaseService();
      if (_isEdit) {
        await pb.updateMaintenanceRecord(
          id: widget.record.id,
          name: name,
          machineId: _machineId!,
          completedDate: _date.text.trim(),
          note: _note.text,
          updatedByEmail: email,
        );
      } else {
        await pb.createMaintenanceRecord(
          name: name,
          machineId: _machineId!,
          completedDate: _date.text.trim(),
          note: _note.text,
          updatedByEmail: email,
          photoFiles: _pendingPhotos.isEmpty
              ? null
              : _pendingPhotoMultipart(_pendingPhotos),
        );
      }
      if (mounted) _close(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildPhotosSection() {
    if (_isEdit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Photos',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),
          PartImagesPanel(
            recordId: widget.record.id as String?,
            collectionName: 'maintenance_records',
            fieldName: 'photos',
            filenames: _photoFilenames,
            maxFiles: 8,
            allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
            emptyHint: 'Click to add photos.',
            addTileLabel: 'Add photo',
            onFilenamesChanged: (list) => setState(() {
              _photoFilenames = list;
              _photosDirty = true;
            }),
          ),
        ],
      );
    }
    return _buildPendingPhotosSection(
      photos: _pendingPhotos,
      onChanged: (next) => setState(() => _pendingPhotos = next),
    );
  }

  void _close([bool saved = false]) {
    Navigator.pop(context, saved || _photosDirty);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit record' : 'Add record'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _date,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Completed date',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: _pickDate,
                  ),
                ),
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _machineId != null &&
                              _machines.any((m) => m.id == _machineId)
                          ? _machineId
                          : null,
                      decoration: const InputDecoration(labelText: 'Machine'),
                      items: _machines
                          .map(
                            (m) => DropdownMenuItem<String>(
                              value: m.id as String,
                              child: Text('${m.data['name'] ?? ''}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _machineId = v),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add machine',
                    onPressed: _addMachineInline,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note'),
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              _buildPhotosSection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => _close(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

class _MaintenanceScheduleDialog extends StatefulWidget {
  final dynamic schedule;
  final List<dynamic> machines;
  final Future<bool?> Function() onAddMachine;

  const _MaintenanceScheduleDialog({
    this.schedule,
    required this.machines,
    required this.onAddMachine,
  });

  @override
  State<_MaintenanceScheduleDialog> createState() =>
      _MaintenanceScheduleDialogState();
}

class _MaintenanceScheduleDialogState extends State<_MaintenanceScheduleDialog> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _freq;
  late final TextEditingController _lead;
  late final TextEditingController _nextDue;
  String _unit = 'days';
  String? _machineId;
  bool _active = true;
  bool _saving = false;
  List<dynamic> _machines = [];

  bool get _isEdit => widget.schedule != null;

  @override
  void initState() {
    super.initState();
    _machines = List<dynamic>.from(widget.machines);
    final data = widget.schedule == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(widget.schedule.data as Map);
    _name = TextEditingController(text: '${data['name'] ?? ''}');
    _note = TextEditingController(text: '${data['note'] ?? ''}');
    final fv = data['frequency_value'];
    _freq = TextEditingController(
      text: fv == null ? '30' : '${fv is num ? fv.toInt() : fv}',
    );
    _lead = TextEditingController(text: '${leadDaysOf(data)}');
    final rawDue = '${data['next_due_date'] ?? ''}'.trim();
    _nextDue = TextEditingController(
      text: rawDue.length >= 10
          ? rawDue.substring(0, 10)
          : formatMaintenanceDate(todayDate()),
    );
    final u = '${data['frequency_unit'] ?? 'days'}';
    _unit = (u == 'weeks' || u == 'months') ? u : 'days';
    _active = scheduleIsActive(data);
    final mid = data['machine']?.toString();
    _machineId = (mid != null && mid.isNotEmpty)
        ? mid
        : (_machines.isNotEmpty ? _machines.first.id as String : null);
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _freq.dispose();
    _lead.dispose();
    _nextDue.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    var initial = todayDate();
    try {
      initial = DateTime.parse(_nextDue.text);
    } catch (_) {}
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _nextDue.text = formatMaintenanceDate(picked));
  }

  Future<void> _addMachineInline() async {
    final ok = await widget.onAddMachine();
    if (ok == true && mounted) {
      final machines = await PocketBaseService().getMaintenanceMachines();
      setState(() {
        _machines = machines;
        _machineId ??= machines.isNotEmpty ? machines.first.id as String : null;
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final freq = int.tryParse(_freq.text.trim()) ?? 0;
    final lead = int.tryParse(_lead.text.trim()) ?? 7;
    if (name.isEmpty ||
        _machineId == null ||
        _machineId!.isEmpty ||
        freq < 1 ||
        _nextDue.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name, machine, frequency ≥ 1, and next due required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final email = AuthService.instance.email;
    final lastRaw = _isEdit
        ? '${widget.schedule.data['last_completed_date'] ?? ''}'.trim()
        : '';
    try {
      final pb = PocketBaseService();
      if (_isEdit) {
        await pb.updateMaintenanceSchedule(
          id: widget.schedule.id,
          name: name,
          machineId: _machineId!,
          frequencyValue: freq,
          frequencyUnit: _unit,
          nextDueDate: _nextDue.text.trim(),
          lastCompletedDate: lastRaw.length >= 10 ? lastRaw.substring(0, 10) : null,
          note: _note.text,
          leadDays: lead.clamp(0, 3650),
          active: _active,
          updatedByEmail: email,
        );
      } else {
        await pb.createMaintenanceSchedule(
          name: name,
          machineId: _machineId!,
          frequencyValue: freq,
          frequencyUnit: _unit,
          nextDueDate: _nextDue.text.trim(),
          note: _note.text,
          leadDays: lead.clamp(0, 3650),
          active: _active,
          updatedByEmail: email,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit schedule' : 'Add schedule'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Spindle grease',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _machineId != null &&
                              _machines.any((m) => m.id == _machineId)
                          ? _machineId
                          : null,
                      decoration: const InputDecoration(labelText: 'Machine'),
                      items: _machines
                          .map(
                            (m) => DropdownMenuItem<String>(
                              value: m.id as String,
                              child: Text('${m.data['name'] ?? ''}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _machineId = v),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add machine',
                    onPressed: _addMachineInline,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _freq,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Every'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: const [
                        DropdownMenuItem(value: 'days', child: Text('Days')),
                        DropdownMenuItem(value: 'weeks', child: Text('Weeks')),
                        DropdownMenuItem(
                          value: 'months',
                          child: Text('Months'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _unit = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nextDue,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Next due',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: _pickDue,
                  ),
                ),
                onTap: _pickDue,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lead,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Alert within (days)',
                  helperText: 'Due soon when within this many days of next due',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Paused schedules stay listed but don’t alert'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note / how-to'),
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

class _ManageMachinesDialog extends StatefulWidget {
  final List<dynamic> machines;
  final Future<void> Function() onChanged;

  const _ManageMachinesDialog({
    required this.machines,
    required this.onChanged,
  });

  @override
  State<_ManageMachinesDialog> createState() => _ManageMachinesDialogState();
}

class _ManageMachinesDialogState extends State<_ManageMachinesDialog> {
  late List<dynamic> _machines;

  @override
  void initState() {
    super.initState();
    _machines = List<dynamic>.from(widget.machines);
  }

  Future<void> _reload() async {
    final machines = await PocketBaseService().getMaintenanceMachines();
    if (!mounted) return;
    setState(() => _machines = machines);
    await widget.onChanged();
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add machine'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Machine name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final nextOrder = _machines.isEmpty
        ? 10
        : ((_machines
                .map((m) => (m.data['sort_order'] as num?)?.toInt() ?? 0)
                .fold<int>(0, (a, b) => a > b ? a : b)) +
            10);
    await PocketBaseService().createMaintenanceMachine(
      name: name,
      sortOrder: nextOrder,
    );
    await _reload();
  }

  Future<void> _rename(dynamic machine) async {
    final controller =
        TextEditingController(text: '${machine.data['name'] ?? ''}');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename machine'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Machine name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await PocketBaseService().updateMaintenanceMachine(
      id: machine.id,
      name: name,
    );
    await _reload();
  }

  Future<void> _delete(dynamic machine) async {
    final label = '${machine.data['name'] ?? 'machine'}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete machine'),
        content: Text(
          'Delete "$label"? Records/schedules that use it must be reassigned first.',
        ),
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
    if (confirm != true) return;
    try {
      await PocketBaseService().deleteMaintenanceMachine(machine.id);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Machines'),
      content: SizedBox(
        width: 360,
        child: _machines.isEmpty
            ? const Text('No machines yet. Add one for the next tool.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _machines.length,
                itemBuilder: (context, index) {
                  final m = _machines[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${m.data['name'] ?? ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _rename(m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(m),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add machine'),
        ),
      ],
    );
  }
}
