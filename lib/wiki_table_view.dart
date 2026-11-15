import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pocketbase/pocketbase.dart';

import 'app_date_field.dart';
import 'auth_service.dart';
import 'pocketbase_service.dart';
import 'wiki_table_models.dart';

/// Loads and renders one wiki table (embedded in a page).
class WikiTableEmbed extends StatefulWidget {
  const WikiTableEmbed({
    super.key,
    required this.tableId,
    this.canEdit = false,
  });

  final String tableId;
  final bool canEdit;

  @override
  State<WikiTableEmbed> createState() => _WikiTableEmbedState();
}

class _WikiTableEmbedState extends State<WikiTableEmbed> {
  RecordModel? _table;
  List<RecordModel> _rows = [];
  List<WikiTableColumn> _columns = [];
  bool _loading = true;
  String? _error;
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WikiTableEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableId != widget.tableId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pb = PocketBaseService();
      final table = await pb.getWikiTable(widget.tableId);
      final rows = await pb.getWikiTableRows(widget.tableId);
      if (!mounted) return;
      setState(() {
        _table = table;
        _rows = rows;
        _columns = parseWikiTableColumns(table.data['columns_json']?.toString());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openSchemaEditor() async {
    final table = _table;
    if (table == null) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => _WikiTableSchemaDialog(
        table: table,
        columns: List.of(_columns),
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _addRow() async {
    final table = _table;
    if (table == null) return;
    final values = <String, dynamic>{};
    for (final c in _columns) {
      if (c.type == 'checkbox') values[c.id] = false;
      if (c.type == 'formula') continue;
    }
    // Newest rows at top (ascending sort_order; use below current min).
    var minSort = 0;
    for (final r in _rows) {
      final raw = r.data['sort_order'];
      final n = raw is int ? raw : int.tryParse('$raw') ?? 0;
      if (n < minSort) minSort = n;
    }
    await PocketBaseService().createWikiTableRow(
      tableId: table.id,
      valuesJson: encodeWikiTableValues(values),
      sortOrder: _rows.isEmpty ? 0 : minSort - 1,
    );
    await _load();
  }

  Future<void> _deleteRow(RecordModel row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete row?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PocketBaseService().deleteWikiTableRow(row.id);
    await _load();
  }

  Future<void> _saveCell(
    RecordModel row,
    WikiTableColumn col,
    dynamic value,
  ) async {
    final values = parseWikiTableValues(row.data['values_json']?.toString());
    final prev = values[col.id];
    if (prev == value || '$prev' == '$value') return;
    values[col.id] = value;
    final updated = await PocketBaseService().updateWikiTableRow(row.id, {
      'values_json': encodeWikiTableValues(values),
    });
    if (!mounted) return;
    setState(() {
      final i = _rows.indexWhere((r) => r.id == row.id);
      if (i >= 0) _rows[i] = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Table unavailable: $_error',
          style: textTheme.bodySmall?.copyWith(color: scheme.error),
        ),
      );
    }
    final table = _table!;
    final title = wikiTableTitle(table);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.canEdit) ...[
                  IconButton(
                    tooltip: 'Edit columns',
                    icon: const Icon(Icons.view_column_outlined, size: 20),
                    onPressed: _openSchemaEditor,
                  ),
                  IconButton(
                    tooltip: 'Add row',
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: _columns.isEmpty ? null : _addRow,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          if (_columns.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.canEdit
                    ? 'No columns yet. Tap the columns icon to define this table.'
                    : 'This table has no columns.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
                scrollbars: false,
              ),
              child: Scrollbar(
                controller: _hScroll,
                thumbVisibility: true,
                trackVisibility: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  // Keep last row above the always-visible scrollbar.
                  padding: const EdgeInsets.only(bottom: 18),
                  child: DataTable(
                    headingRowHeight: 32,
                    dataRowMinHeight: 32,
                    dataRowMaxHeight: 36,
                    columnSpacing: 6,
                    horizontalMargin: 8,
                    dividerThickness: 0,
                    columns: [
                      for (final c in _columns)
                        DataColumn(
                          label: SizedBox(
                            width: _columnWidth(c),
                            child: Text(
                              c.name.isEmpty ? c.id : c.name,
                              style: textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      if (widget.canEdit)
                        const DataColumn(label: SizedBox(width: 36)),
                    ],
                    rows: [
                      for (final row in _rows)
                        DataRow(
                          cells: [
                            for (final c in _columns)
                              DataCell(
                                _cellWidget(row, c),
                              ),
                            if (widget.canEdit)
                              DataCell(
                                IconButton(
                                  icon:
                                      const Icon(Icons.delete_outline, size: 18),
                                  tooltip: 'Delete row',
                                  onPressed: () => _deleteRow(row),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _columnWidth(WikiTableColumn col) {
    switch (col.type) {
      case 'checkbox':
        return 56;
      case 'date':
        return 108;
      case 'number':
        return 72;
      case 'formula':
        return 72;
      case 'text':
      default:
        final n = col.name.toLowerCase();
        if (n.contains('note')) return 260;
        return 140;
    }
  }

  Widget _cellWidget(RecordModel row, WikiTableColumn col) {
    final values = parseWikiTableValues(row.data['values_json']?.toString());
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (col.type == 'formula') {
      final v = wikiTableCellDisplay(col, values);
      return SizedBox(
        width: _columnWidth(col),
        child: Text(
          v?.toString() ?? '',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    if (!widget.canEdit) {
      return SizedBox(
        width: _columnWidth(col),
        child: Text(
          _formatReadValue(col, values[col.id]),
          style: textTheme.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    switch (col.type) {
      case 'checkbox':
        final checked = values[col.id] == true;
        return SizedBox(
          height: 28,
          child: Checkbox(
            value: checked,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => _saveCell(row, col, v ?? false),
          ),
        );
      case 'date':
        return _InlineDateCell(
          key: ValueKey('${row.id}-${col.id}-date'),
          value: values[col.id]?.toString(),
          onCommit: (iso) => _saveCell(row, col, iso),
        );
      case 'number':
        return _InlineTextCell(
          key: ValueKey('${row.id}-${col.id}-num'),
          value: values[col.id]?.toString() ?? '',
          isNumber: true,
          width: _columnWidth(col),
          onCommit: (text) async {
            final t = text.trim();
            if (t.isEmpty) {
              await _saveCell(row, col, null);
            } else {
              await _saveCell(row, col, num.tryParse(t));
            }
          },
        );
      case 'text':
      default:
        return _InlineTextCell(
          key: ValueKey('${row.id}-${col.id}-text'),
          value: values[col.id]?.toString() ?? '',
          isNumber: false,
          width: _columnWidth(col),
          onCommit: (text) => _saveCell(row, col, text),
        );
    }
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String _formatReadValue(WikiTableColumn col, dynamic value) {
    if (value == null || '$value'.isEmpty) return '—';
    if (col.type == 'checkbox') return value == true ? '✓' : '';
    if (col.type == 'date') {
      final d = _parseDate(value);
      if (d == null) return value.toString();
      return DateFormat.yMMMd().format(d);
    }
    return value.toString();
  }
}

/// Compact inline field — type in place; saves on Enter or focus loss.
class _InlineTextCell extends StatefulWidget {
  const _InlineTextCell({
    super.key,
    required this.value,
    required this.isNumber,
    required this.onCommit,
    this.width,
  });

  final String value;
  final bool isNumber;
  final double? width;
  final Future<void> Function(String text) onCommit;

  @override
  State<_InlineTextCell> createState() => _InlineTextCellState();
}

class _InlineTextCellState extends State<_InlineTextCell> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus && _dirty) {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _InlineTextCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value && !_dirty) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    _dirty = false;
    await widget.onCommit(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? (widget.isNumber ? 72.0 : 140.0);
    return SizedBox(
      width: w,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        style: Theme.of(context).textTheme.bodySmall,
        keyboardType: widget.isNumber
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        inputFormatters: widget.isNumber
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
            : null,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => _dirty = true,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

class _InlineDateCell extends StatefulWidget {
  const _InlineDateCell({
    super.key,
    required this.value,
    required this.onCommit,
  });

  final String? value;
  final Future<void> Function(String? iso) onCommit;

  @override
  State<_InlineDateCell> createState() => _InlineDateCellState();
}

class _InlineDateCellState extends State<_InlineDateCell> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _display(widget.value));
  }

  @override
  void didUpdateWidget(covariant _InlineDateCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _ctrl.text = _display(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _display(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    return formatAppDateText(raw);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: AppDateField(
        controller: _ctrl,
        isDense: true,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        decoration: const InputDecoration(
          isDense: true,
          hintText: '11/14/2026',
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          border: OutlineInputBorder(),
        ),
        onDateChanged: (d) async {
          if (d == null) {
            await widget.onCommit(null);
          } else {
            await widget.onCommit(formatAppDateIso(d));
          }
        },
      ),
    );
  }
}

class _WikiTableSchemaDialog extends StatefulWidget {
  const _WikiTableSchemaDialog({
    required this.table,
    required this.columns,
  });

  final RecordModel table;
  final List<WikiTableColumn> columns;

  @override
  State<_WikiTableSchemaDialog> createState() => _WikiTableSchemaDialogState();
}

class _WikiTableSchemaDialogState extends State<_WikiTableSchemaDialog> {
  late final TextEditingController _titleCtrl;
  late List<WikiTableColumn> _columns;
  final _nameCtrls = <String, TextEditingController>{};
  final _formulaCtrls = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: wikiTableTitle(widget.table));
    _columns = List.of(widget.columns);
    for (final c in _columns) {
      _nameCtrls[c.id] = TextEditingController(text: c.name);
      _formulaCtrls[c.id] = TextEditingController(text: c.formula ?? '');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _nameCtrls.values) {
      c.dispose();
    }
    for (final c in _formulaCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _nameCtrl(String id) =>
      _nameCtrls.putIfAbsent(id, () => TextEditingController());

  TextEditingController _formulaCtrl(String id) =>
      _formulaCtrls.putIfAbsent(id, () => TextEditingController());

  /// Pull latest text from fields (avoids lost names when Save is hit mid-edit).
  List<WikiTableColumn> _columnsFromFields() {
    return [
      for (final c in _columns)
        c.copyWith(
          name: _nameCtrl(c.id).text.trim(),
          formula: _formulaCtrl(c.id).text.trim(),
        ),
    ];
  }

  void _addColumn() {
    final id = newWikiTableColumnId(_columns);
    final name = 'Column ${_columns.length + 1}';
    _nameCtrls[id] = TextEditingController(text: name);
    _formulaCtrls[id] = TextEditingController();
    setState(() {
      _columns.add(
        WikiTableColumn(id: id, name: name, type: 'text'),
      );
    });
  }

  void _removeColumn(int index) {
    final id = _columns[index].id;
    setState(() => _columns.removeAt(index));
    _nameCtrls.remove(id)?.dispose();
    _formulaCtrls.remove(id)?.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final columns = _columnsFromFields();

    final seen = <String>{};
    final dupes = <String>{};
    for (final c in columns) {
      final key = c.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (!seen.add(key)) dupes.add(c.name.trim());
    }
    if (dupes.isNotEmpty) {
      final list = dupes.join(', ');
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Duplicate column names'),
          content: Text(
            'These names are used more than once:\n\n$list\n\n'
            'That can make the table confusing. Save anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _columns = columns;
    });
    try {
      final auth = AuthService.instance;
      await PocketBaseService().updateWikiTable(widget.table.id, {
        'title': title,
        'columns_json': encodeWikiTableColumns(columns),
        'updated_by_email': auth.email ?? '',
        'updated_by_name': auth.displayName ?? '',
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth =
        (MediaQuery.sizeOf(context).width * 0.9).clamp(560.0, 880.0);
    return AlertDialog(
      title: const Text('Edit table'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                enabled: !_saving,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Columns',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _saving ? null : _addColumn,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _columns.length; i++) ...[
                _columnEditor(i),
                const SizedBox(height: 8),
              ],
              if (_columns.any((c) => c.type == 'formula'))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Formula tip: use column ids (c1, c2, …) with + − * /, e.g. c3-c4',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _columnEditor(int index) {
    final col = _columns[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  col.id,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: TextField(
                controller: _nameCtrl(col.id),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                enabled: !_saving,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value:
                    kWikiTableColumnTypes.contains(col.type) ? col.type : 'text',
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final t in kWikiTableColumnTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: _saving
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() {
                          _columns[index] = col.copyWith(
                            name: _nameCtrl(col.id).text.trim(),
                            formula: _formulaCtrl(col.id).text.trim(),
                            type: v,
                          );
                        });
                      },
              ),
            ),
            IconButton(
              tooltip: 'Remove column',
              onPressed: _saving ? null : () => _removeColumn(index),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        if (col.type == 'formula') ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: TextField(
              controller: _formulaCtrl(col.id),
              decoration: InputDecoration(
                labelText: 'Formula',
                hintText: 'e.g. c8-c9',
                helperText: 'Use ids (${_columns.map((c) => c.id).join(', ')})',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              enabled: !_saving,
            ),
          ),
        ],
      ],
    );
  }
}

/// Creates a wiki table linked to [pageId] and returns embed markdown token.
Future<String?> createWikiTableAndEmbedToken(
  BuildContext context, {
  required String pageId,
}) async {
  final auth = AuthService.instance;
  final columns = [
    WikiTableColumn(id: 'c1', name: 'Name', type: 'text'),
    WikiTableColumn(id: 'c2', name: 'Date', type: 'date'),
    WikiTableColumn(id: 'c3', name: 'Done', type: 'checkbox'),
  ];
  try {
    final table = await PocketBaseService().createWikiTable(
      title: 'New table',
      columnsJson: encodeWikiTableColumns(columns),
      pageId: pageId,
      updatedByEmail: auth.email,
      updatedByName: auth.displayName,
    );
    return wikiTableEmbedToken(table.id);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create table: $e'), backgroundColor: Colors.red),
      );
    }
    return null;
  }
}
