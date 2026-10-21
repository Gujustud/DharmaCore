import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pocketbase_service.dart';

/// Upload / view files on a PocketBase file field (e.g. `part_images`, `photos`).
class PartImagesPanel extends StatefulWidget {
  final String? recordId;
  final String collectionName;
  final String fieldName;
  final List<String> filenames;
  final ValueChanged<List<String>> onFilenamesChanged;
  final bool fillHeight;
  final int maxFiles;
  final List<String> allowedExtensions;
  final String emptyHint;
  final String saveFirstHint;
  final String addTileLabel;

  const PartImagesPanel({
    super.key,
    required this.recordId,
    required this.collectionName,
    this.fieldName = 'part_images',
    required this.filenames,
    required this.onFilenamesChanged,
    this.fillHeight = false,
    this.maxFiles = 10,
    this.allowedExtensions = const [
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'pdf',
    ],
    this.emptyHint = 'Click to add images or PDFs.',
    this.saveFirstHint = 'Save this record first to upload files.',
    this.addTileLabel = 'Add image\nor PDF',
  });

  static List<String> normalizeFilenames(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final s = value.toString();
    return s.isEmpty ? [] : [s];
  }

  @override
  State<PartImagesPanel> createState() => _PartImagesPanelState();
}

class _PartImagesPanelState extends State<PartImagesPanel> {
  bool _uploading = false;
  RecordModel? _record;

  int get _maxFiles => widget.maxFiles;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  @override
  void didUpdateWidget(PartImagesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordId != widget.recordId) {
      _loadRecord();
    }
  }

  Future<void> _loadRecord() async {
    final id = widget.recordId;
    if (id == null || id.isEmpty) {
      setState(() => _record = null);
      return;
    }
    try {
      final r = await PocketBaseService().pb.collection(widget.collectionName).getOne(id);
      if (mounted) setState(() => _record = r);
    } catch (_) {
      if (mounted) setState(() => _record = null);
    }
  }

  bool _isPdf(String name) => name.toLowerCase().endsWith('.pdf');

  String? _fileUrl(String filename, {bool thumb = true}) {
    final record = _record;
    if (record == null || filename.isEmpty) return null;
    final pb = PocketBaseService().pb;
    if (thumb && !_isPdf(filename)) {
      return pb.files.getUrl(record, filename, thumb: '300x300f').toString();
    }
    return pb.files.getUrl(record, filename).toString();
  }

  void _applyRecord(RecordModel updated) {
    setState(() => _record = updated);
    widget.onFilenamesChanged(
      PartImagesPanel.normalizeFilenames(updated.data[widget.fieldName]),
    );
  }

  Future<void> _pickAndUpload() async {
    final id = widget.recordId;
    if (id == null) return;
    if (widget.filenames.length >= _maxFiles) {
      _snack('Maximum $_maxFiles files per record.');
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.allowedExtensions,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final pb = PocketBaseService().pb;
      RecordModel? last;
      var count = widget.filenames.length;

      for (final file in result.files) {
        if (count >= _maxFiles) break;
        final bytes = file.bytes ?? await file.readAsBytes();
        if (bytes.isEmpty) continue;

        final name = _safeFilename(file.name, bytes);
        last = await pb.collection(widget.collectionName).update(
          id,
          files: [
            http.MultipartFile.fromBytes(
              '${widget.fieldName}+',
              bytes,
              filename: name,
            ),
          ],
        );
        count++;
      }

      if (last != null) {
        _applyRecord(last);
        if (mounted) {
          _snack('Upload complete', success: true);
        }
      }
    } catch (e) {
      if (mounted) _snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _safeFilename(String? name, Uint8List bytes) {
    if (name != null && name.trim().isNotEmpty) return name.trim();
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image-${DateTime.now().millisecondsSinceEpoch}.png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
    }
    return 'file-${DateTime.now().millisecondsSinceEpoch}.bin';
  }

  Future<void> _deleteFile(String filename) async {
    final id = widget.recordId;
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Delete "$filename"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final updated = await PocketBaseService().pb.collection(widget.collectionName).update(
        id,
        body: {'${widget.fieldName}-': filename},
      );
      _applyRecord(updated);
      if (mounted) _snack('File deleted', success: true);
    } catch (e) {
      if (mounted) _snack('Delete failed: $e');
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : null,
      ),
    );
  }

  void _showImagePreview(String url, String alt) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          child: SizedBox(
            width: size.width * 0.92,
            height: size.height * 0.85,
            child: Column(
              children: [
                AppBar(
                  title: Text(alt, overflow: TextOverflow.ellipsis),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Expanded(
                  child: InteractiveViewer(
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyDropZone() {
    return InkWell(
      onTap: _uploading ? null : _pickAndUpload,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: widget.fillHeight ? 120 : 0),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _uploading
              ? 'Uploading…'
              : '${widget.emptyHint}\n(Max $_maxFiles files)',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ),
    );
  }

  Widget _saveFirstHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        widget.saveFirstHint,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
    );
  }

  Widget _fileTile(String filename, int index) {
    final fullUrl = _fileUrl(filename, thumb: false);
    if (fullUrl == null) return const SizedBox.shrink();

    if (_isPdf(filename)) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _openUrl(fullUrl),
                child: ColoredBox(
                  color: Colors.grey.shade200,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf, size: 40, color: Colors.red.shade700),
                      const SizedBox(height: 4),
                      const Text('PDF', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                    onPressed: () => _deleteFile(filename),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final thumbUrl = _fileUrl(filename) ?? fullUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            onTap: () => _showImagePreview(fullUrl, 'Part ${index + 1}'),
            child: Image.network(
              thumbUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                onTap: () => _deleteFile(filename),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addTile() {
    return Card(
      child: InkWell(
        onTap: _uploading ? null : _pickAndUpload,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 32, color: Colors.grey[600]),
            const SizedBox(height: 4),
            Text(
              widget.addTileLabel,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recordId == null || widget.recordId!.isEmpty) {
      return _saveFirstHint();
    }

    final images = widget.filenames;
    final canAddMore = images.length < _maxFiles;

    if (images.isEmpty) {
      return _emptyDropZone();
    }

    final itemCount = images.length + (canAddMore ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // shrinkWrap + non-scrollable: parent quote screen is already a ScrollView.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (canAddMore && index == itemCount - 1) {
              return _addTile();
            }
            return _fileTile(images[index], index);
          },
        ),
        if (_uploading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}
