import 'package:flutter/material.dart';

import 'material_form_icons.dart';
import 'material_size_parse.dart';
import 'models.dart';
import 'pocketbase_service.dart';

/// Result of [showShopMaterialEditor].
///
/// [purchaseLengthIn] is bar length in inches when the Length field was set.
/// It is never written into catalog [ShopMaterial.sizeLabel].
class ShopMaterialEditorResult {
  final ShopMaterial material;
  final double? purchaseLengthIn;

  const ShopMaterialEditorResult({
    required this.material,
    this.purchaseLengthIn,
  });
}

/// Shared create/edit dialog for [ShopMaterial].
///
/// Always shows Size (cross-section) + Length. Catalog stores Size only.
/// Length seeds a purchase line when creating from purchases, and on edit
/// backfills purchase lines that still lack `length_in`.
Future<ShopMaterialEditorResult?> showShopMaterialEditor(
  BuildContext context, {
  ShopMaterial? existing,
  /// Kept for call-site compatibility; Length is always shown.
  bool capturePurchaseLength = true,
}) {
  return showDialog<ShopMaterialEditorResult>(
    context: context,
    builder: (ctx) => _ShopMaterialEditorDialog(existing: existing),
  );
}

class _ShopMaterialEditorDialog extends StatefulWidget {
  const _ShopMaterialEditorDialog({this.existing});

  final ShopMaterial? existing;

  @override
  State<_ShopMaterialEditorDialog> createState() =>
      _ShopMaterialEditorDialogState();
}

class _ShopMaterialEditorDialogState extends State<_ShopMaterialEditorDialog> {
  static const _gradeSuggestionsMax = 25;

  late final TextEditingController _gradeCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _lengthCtrl;
  late final TextEditingController _notesCtrl;
  late String _form;
  late String _unit;
  bool _saving = false;
  List<String> _gradeSuggestions = [];

  bool get _isEdit =>
      widget.existing != null && widget.existing!.id.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _gradeCtrl = TextEditingController(text: existing?.grade ?? '');
    final rawSize = existing?.sizeLabel ?? '';
    final stripped = stripTrailingLengthFromSizeLabel(rawSize);
    final embeddedLen = barLengthFromSizeLabel(rawSize);
    _sizeCtrl = TextEditingController(text: stripped ?? rawSize);
    _lengthCtrl = TextEditingController(
      text: embeddedLen != null && embeddedLen > 0
          ? formatInchesValue(embeddedLen)
          : '',
    );
    _notesCtrl = TextEditingController(text: existing?.notes ?? '');
    _form = canonicalMaterialForm(existing?.form ?? 'flat');
    _unit = existing?.unit ?? 'ea';
    _loadGradeSuggestions();
  }

  Future<void> _loadGradeSuggestions() async {
    try {
      final records = await PocketBaseService().getMaterials();
      final grades = <String>{};
      for (final r in records) {
        final g = ShopMaterial.fromRecord(r).grade.trim();
        if (g.isNotEmpty) grades.add(g);
      }
      final list = grades.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (mounted) setState(() => _gradeSuggestions = list);
    } catch (_) {
      // Suggestions are optional; typing a new grade still works.
    }
  }

  Iterable<String> _filterGrades(String text) {
    if (_gradeSuggestions.isEmpty) return const [];
    final q = text.trim().toLowerCase();
    final matches = q.isEmpty
        ? _gradeSuggestions
        : _gradeSuggestions.where((g) => g.toLowerCase().contains(q));
    return matches.take(_gradeSuggestionsMax);
  }

  double? _parseLengthField() {
    final raw = _lengthCtrl.text.trim().replaceAll(RegExp(r'[^0-9.]'), '');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    return v;
  }

  /// Size field → catalog cross-section; Length field (or trailing in Size).
  ({String sizeLabel, double? lengthIn}) _normalizedSizeAndLength() {
    var size = _sizeCtrl.text.trim();
    var lengthIn = _parseLengthField();
    final fromSize = barLengthFromSizeLabel(size);
    final stripped = stripTrailingLengthFromSizeLabel(size);
    if (stripped != null) {
      size = stripped;
      lengthIn ??= fromSize;
    }
    return (sizeLabel: size, lengthIn: lengthIn);
  }

  @override
  void dispose() {
    _gradeCtrl.dispose();
    _sizeCtrl.dispose();
    _lengthCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final grade = _gradeCtrl.text.trim();
    final normalized = _normalizedSizeAndLength();
    final size = normalized.sizeLabel;
    final purchaseLen = normalized.lengthIn;
    if (grade.isEmpty || size.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grade and size are required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final pb = PocketBaseService();
      final existing = widget.existing;
      final isEdit = existing != null && existing.id.trim().isNotEmpty;
      final rec = isEdit
          ? await pb.updateMaterial(
              existing.id,
              grade: grade,
              form: canonicalMaterialForm(_form),
              sizeLabel: size,
              unit: _unit,
              notes: _notesCtrl.text,
            )
          : await pb.createMaterial(
              grade: grade,
              form: canonicalMaterialForm(_form),
              sizeLabel: size,
              unit: _unit,
              notes: _notesCtrl.text,
            );
      final material = ShopMaterial.fromRecord(rec);
      // Editing a length-in-size catalog row: keep Length on purchase lines.
      if (isEdit && purchaseLen != null && purchaseLen > 0) {
        try {
          await pb.fillMissingPurchaseLengths(material.id, purchaseLen);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        ShopMaterialEditorResult(
          material: material,
          purchaseLengthIn: purchaseLen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit material' : 'New material'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _gradeCtrl.text),
                optionsBuilder: (textEditingValue) =>
                    _filterGrades(textEditingValue.text),
                onSelected: (grade) {
                  _gradeCtrl.text = grade;
                },
                optionsMaxHeight: 240,
                fieldViewBuilder: (
                  context,
                  textEditingController,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Grade / alloy',
                      hintText: 'e.g. 4140, 6061-T6',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    enabled: !_saving,
                    onChanged: (v) => _gradeCtrl.text = v,
                    onSubmitted: (_) => onFieldSubmitted(),
                  );
                },
              ),
              const SizedBox(height: 12),
              MaterialFormIconRow(
                value: _form,
                enabled: !_saving,
                onChanged: (v) => setState(() => _form = v),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _sizeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Size',
                        hintText: 'Cross-section, e.g. 3×6',
                        helperText: 'No bar length here',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _lengthCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Length',
                        hintText: 'in',
                        helperText: 'Per bar',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: !_saving,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _unit,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'ea', child: Text('Each')),
                  DropdownMenuItem(value: 'ft', child: Text('Feet')),
                  DropdownMenuItem(value: 'in', child: Text('Inches')),
                  DropdownMenuItem(value: 'lb', child: Text('Pounds')),
                  DropdownMenuItem(value: 'kg', child: Text('Kilograms')),
                ],
                onChanged: _saving
                    ? null
                    : (v) {
                        if (v != null) setState(() => _unit = v);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                enabled: !_saving,
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
          child: Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
