import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:pocketbase/pocketbase.dart';

import 'auth_service.dart';
import 'pocketbase_service.dart';
import 'workspace_scaffold.dart';
import 'wiki_page_utils.dart';
import 'wiki_table_models.dart';
import 'wiki_table_view.dart';

MediaType? _wikiUploadContentType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.pdf')) return MediaType('application', 'pdf');
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return MediaType('image', 'jpeg');
  }
  if (lower.endsWith('.gif')) return MediaType('image', 'gif');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');
  return null;
}

http.MultipartFile _wikiAttachmentPart(String filename, List<int> bytes) {
  return http.MultipartFile.fromBytes(
    'attachments+', // append; bare "attachments" replaces in PB 0.23+
    bytes,
    filename: filename,
    contentType: _wikiUploadContentType(filename),
  );
}

/// Create or edit a wiki page (markdown body + attachments).
class WikiEditScreen extends StatefulWidget {
  final RecordModel? page;
  final String? defaultParentId;
  final List<RecordModel> allPages;

  const WikiEditScreen({
    super.key,
    this.page,
    this.defaultParentId,
    required this.allPages,
  });

  @override
  State<WikiEditScreen> createState() => _WikiEditScreenState();
}

class _WikiEditScreenState extends State<WikiEditScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _sort = TextEditingController(text: '0');
  final _bodyFocus = FocusNode();
  String _visibility = 'everyone';
  String? _parentId;
  bool _saving = false;
  bool _uploading = false;
  RecordModel? _record;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _record = widget.page;
    final p = widget.page;
    if (p != null) {
      _title.text = wikiTitle(p);
      _body.text = wikiBody(p);
      _visibility = wikiVisibility(p);
      _parentId = wikiParentId(p);
      _sort.text = '${wikiSortOrder(p)}';
    } else {
      _parentId = widget.defaultParentId;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _sort.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _replaceBodyRange(int start, int end, String replacement) {
    final text = _body.text;
    final next = text.replaceRange(start, end, replacement);
    _body.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _bodyFocus.requestFocus();
  }

  (int start, int end, String selected) _bodySelection() {
    final value = _body.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final selected = start < end ? text.substring(start, end) : '';
    return (start, end, selected);
  }

  void _wrapBodySelection({
    required String prefix,
    required String suffix,
    String placeholder = 'text',
  }) {
    final (start, end, selected) = _bodySelection();
    final inner = selected.isEmpty ? placeholder : selected;
    _replaceBodyRange(start, end, '$prefix$inner$suffix');
  }

  void _wrapBold() {
    final (start, end, selected) = _bodySelection();
    final inner = selected.isEmpty ? 'text' : selected;

    final uWrap = RegExp(r'^<u>([\s\S]*)</u>$').firstMatch(inner);
    if (uWrap != null) {
      final content = uWrap.group(1)!;
      if (content.startsWith('**') && content.endsWith('**')) {
        _wrapBodySelection(prefix: '**', suffix: '**');
        return;
      }
      _replaceBodyRange(start, end, '<u>**$content**</u>');
      return;
    }

    _wrapBodySelection(prefix: '**', suffix: '**');
  }

  void _wrapUnderline() {
    final (start, end, selected) = _bodySelection();
    final inner = selected.isEmpty ? 'text' : selected;

    final wrongOrder = RegExp(r'^\*\*<u>([\s\S]*)</u>\*\*$').firstMatch(inner);
    if (wrongOrder != null) {
      _replaceBodyRange(start, end, '<u>**${wrongOrder.group(1)}**</u>');
      return;
    }

    final boldOnly = RegExp(r'^\*\*([\s\S]*)\*\*$').firstMatch(inner);
    if (boldOnly != null) {
      _replaceBodyRange(start, end, '<u>**${boldOnly.group(1)}**</u>');
      return;
    }

    final uWrap = RegExp(r'^<u>([\s\S]*)</u>$').firstMatch(inner);
    if (uWrap != null) {
      _wrapBodySelection(prefix: '<u>', suffix: '</u>');
      return;
    }

    _wrapBodySelection(prefix: '<u>', suffix: '</u>');
  }

  Set<String> _illegalParentIds() {
    final id = _record?.id;
    if (id == null) return {};
    return {id, ...wikiDescendantIds(widget.allPages, id)};
  }

  Future<void> _save({bool popOnSuccess = true}) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required.')),
      );
      return;
    }
    setState(() => _saving = true);
    final email = AuthService.instance.email ?? '';
    final displayName = AuthService.instance.displayName ?? '';
    final sort = int.tryParse(_sort.text.trim()) ?? 0;
    final body = <String, dynamic>{
      'title': title,
      'body': wikiPrepareMarkdown(_body.text),
      'visibility': _visibility,
      'sort_order': sort,
      'updated_by_email': email,
      'updated_by_name': displayName,
    };
    if (_parentId != null && _parentId!.isNotEmpty) {
      body['parent'] = _parentId;
    } else {
      body['parent'] = null;
    }
    try {
      final col = PocketBaseService().pb.collection('wiki_pages');
      RecordModel saved;
      if (_record == null) {
        saved = await col.create(body: body);
      } else {
        saved = await col.update(_record!.id, body: body);
      }
      if (!mounted) return;
      setState(() {
        _record = saved;
        _saving = false;
      });
      if (popOnSuccess) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickFiles() async {
    var record = _record;
    if (record == null) {
      await _save(popOnSuccess: false);
      record = _record;
    }
    if (record == null || !mounted) return;

    final names = wikiAttachmentNames(record);
    if (names.length >= 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 12 files per page.')),
      );
      return;
    }

    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'pdf'],
    );
    if (files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final remaining = 12 - names.length;
      final uploads = <http.MultipartFile>[];
      for (final f in files) {
        if (uploads.length >= remaining) break;
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;
        uploads.add(_wikiAttachmentPart(f.name, bytes));
      }
      if (uploads.isEmpty) return;
      final updated = await PocketBaseService().pb.collection('wiki_pages').update(
        record.id,
        files: uploads,
      );
      if (mounted) setState(() => _record = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Create a reusable table and insert `{{table:id}}` at the cursor.
  Future<void> _insertTable() async {
    var record = _record;
    if (record == null) {
      await _save(popOnSuccess: false);
      record = _record;
    }
    if (record == null || !mounted) return;

    final token = await createWikiTableAndEmbedToken(
      context,
      pageId: record.id,
    );
    if (token == null || !mounted) return;

    final sel = _body.selection;
    final start = sel.isValid ? sel.start : _body.text.length;
    final end = sel.isValid ? sel.end : start;
    final insert = start > 0 && !_body.text.substring(0, start).endsWith('\n')
        ? '\n$token\n'
        : '$token\n';
    _replaceBodyRange(start, end, insert);
    // Show the live grid (not the raw {{table:…}} token).
    setState(() => _preview = true);
  }

  /// Upload image(s) and insert markdown `![alt](url)` at the cursor.
  Future<void> _insertInlineImages() async {
    var record = _record;
    if (record == null) {
      await _save(popOnSuccess: false);
      record = _record;
    }
    if (record == null || !mounted) return;

    final names = wikiAttachmentNames(record);
    if (names.length >= 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 12 files per page.')),
      );
      return;
    }

    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    );
    if (files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final pb = PocketBaseService().pb;
      final before = wikiAttachmentNames(record).toSet();
      final remaining = 12 - before.length;
      final uploads = <http.MultipartFile>[];
      for (final f in files) {
        if (uploads.length >= remaining) break;
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;
        uploads.add(_wikiAttachmentPart(f.name, bytes));
      }
      if (uploads.isEmpty) return;

      final last = await pb.collection('wiki_pages').update(
        record.id,
        files: uploads,
      );
      final added = wikiAttachmentNames(last).where((n) => !before.contains(n));
      final snippets = <String>[
        for (final name in added)
          '![${name.replaceAll(RegExp(r'\.[^.]+$'), '')}](${pb.files.getUrl(last, name)})',
      ];

      if (mounted) {
        setState(() {
          _record = last;
          _preview = false;
        });
        if (snippets.isNotEmpty) {
          final (start, end, _) = _bodySelection();
          final block = snippets.join('\n\n');
          final needsPadBefore =
              start > 0 && !_body.text.substring(0, start).endsWith('\n');
          final insert = '${needsPadBefore ? '\n\n' : ''}$block\n\n';
          _replaceBodyRange(start, end, insert);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image insert failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeFile(String filename) async {
    final record = _record;
    if (record == null) return;
    try {
      final updated = await PocketBaseService().pb.collection('wiki_pages').update(
        record.id,
        body: {
          'attachments-': [filename],
        },
      );
      if (mounted) setState(() => _record = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Remove failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final illegal = _illegalParentIds();
    final parentChoices = widget.allPages
        .where((p) => !illegal.contains(p.id))
        .toList()
      ..sort((a, b) => wikiTitle(a).toLowerCase().compareTo(wikiTitle(b).toLowerCase()));
    final isNew = widget.page == null;

    return WorkspaceScaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New wiki page' : 'Edit wiki page'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _visibility,
                    decoration: const InputDecoration(
                      labelText: 'Who can read',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'everyone',
                        child: Text('Everyone logged in (incl. shop floor)'),
                      ),
                      DropdownMenuItem(
                        value: 'staff',
                        child: Text('Office only (not jobs_only)'),
                      ),
                      DropdownMenuItem(
                        value: 'owner',
                        child: Text('Owner only'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _visibility = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value:
                        parentChoices.any((p) => p.id == _parentId) ? _parentId : null,
                    decoration: const InputDecoration(
                      labelText: 'Parent page (empty = top-level section)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None (top level)'),
                      ),
                      ...parentChoices.map(
                        (p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(wikiTitle(p)),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _parentId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sort order (lower first)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Body',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Edit'), icon: Icon(Icons.edit_outlined, size: 18)),
                          ButtonSegment(value: true, label: Text('Preview'), icon: Icon(Icons.visibility_outlined, size: 18)),
                        ],
                        selected: {_preview},
                        onSelectionChanged: (s) => setState(() => _preview = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_preview)
                    Container(
                      constraints: const BoxConstraints(minHeight: 240),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: wikiBodyWithTables(
                        context,
                        _body.text,
                        canEditTables: true,
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Bold',
                            onPressed: _wrapBold,
                            icon: const Icon(Icons.format_bold),
                          ),
                          IconButton(
                            tooltip: 'Italic',
                            onPressed: () => _wrapBodySelection(prefix: '*', suffix: '*'),
                            icon: const Icon(Icons.format_italic),
                          ),
                          IconButton(
                            tooltip: 'Underline',
                            onPressed: _wrapUnderline,
                            icon: const Icon(Icons.format_underlined),
                          ),
                          IconButton(
                            tooltip: 'Insert image inline',
                            onPressed: _uploading ? null : _insertInlineImages,
                            icon: const Icon(Icons.image_outlined),
                          ),
                          IconButton(
                            tooltip: 'Insert table',
                            onPressed: _saving || _uploading ? null : _insertTable,
                            icon: const Icon(Icons.table_chart_outlined),
                          ),
                        ],
                      ),
                    ),
                    TextField(
                      controller: _body,
                      focusNode: _bodyFocus,
                      minLines: 12,
                      maxLines: 24,
                      decoration: const InputDecoration(
                        hintText:
                            'B / I / U · Images · Tables (use table button, then Preview)',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    // Live grids for any {{table:id}} tokens while editing markdown.
                    ...[
                      for (final part in splitWikiBodyWithTables(_body.text))
                        if (part.isTable)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: WikiTableEmbed(
                              key: ValueKey(part.tableId),
                              tableId: part.tableId!,
                              canEdit: true,
                            ),
                          ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Images & PDFs', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_uploading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        TextButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.attach_file),
                          label: Text(_record == null ? 'Save page, then attach' : 'Add files'),
                        ),
                    ],
                  ),
                  if (_record != null)
                    ...wikiAttachmentNames(_record!).map((name) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          name.toLowerCase().endsWith('.pdf')
                              ? Icons.picture_as_pdf
                              : Icons.image,
                        ),
                        title: Text(name),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => _removeFile(name),
                        ),
                      );
                    }),
                  if (_record != null && wikiUpdatedEmail(_record!).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Last edit by ${wikiUpdatedByLabel(_record!)} · ${wikiUpdatedLabel(_record!)}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saving ? null : () => _save(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            isNew ? 'ADD PAGE' : 'SAVE CHANGES',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String wikiUpdatedLabel(RecordModel page) {
  final raw = page.data['updated']?.toString();
  if (raw == null || raw.isEmpty) return '';
  try {
    return DateFormat.yMMMd().add_jm().format(DateTime.parse(raw).toLocal());
  } catch (_) {
    return raw;
  }
}
