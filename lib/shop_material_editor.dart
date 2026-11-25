import 'package:flutter/material.dart';

import 'material_form_icons.dart';
import 'models.dart';
import 'pocketbase_service.dart';

/// Result of [showShopMaterialEditor].
///
/// [purchaseLengthIn] is set when [capturePurchaseLength] was true (purchase
/// create flow). It is never written into catalog [ShopMaterial.sizeLabel].
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
/// When [capturePurchaseLength] is true (purchase `+` flow), shows a Length
/// field beside Size. Size is cross-section only; length seeds the purchase line.
Future<ShopMaterialEditorResult?> showShopMaterialEditor(
  BuildContext context, {
  ShopMaterial? existing,
  bool capturePurchaseLength = false,
}) {
  return showDialog<ShopMaterialEditorResult>(
    context: context,
    builder: (ctx) => _ShopMaterialEditorDialog(
      existing: existing,
      capturePurchaseLength: capturePurchaseLength,
    ),
  );
}

class _ShopMaterialEditorDialog extends StatefulWidget {
  const _ShopMaterialEditorDialog({
    this.existing,
    this.capturePurchaseLength = false,
  });

  final ShopMaterial? existing;
  final bool capturePurchaseLength;

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
    _sizeCtrl = TextEditingController(text: existing?.sizeLabel ?? '');
    _lengthCtrl = TextEditingController();
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
    final size = _sizeCtrl.text.trim();
    if (grade.isEmpty || size.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grade and size are required')),
      );
      return;
    }
    double? purchaseLen;
    if (widget.capturePurchaseLength) {
      final raw = _lengthCtrl.text.trim().replaceAll(RegExp(r'[^0-9.]'), '');
      purchaseLen = double.tryParse(raw);
      if (purchaseLen != null && purchaseLen <= 0) purchaseLen = null;
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
      if (!mounted) return;
      Navigator.pop(
        context,
        ShopMaterialEditorResult(
          material: ShopMaterial.fromRecord(rec),
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
              if (widget.capturePurchaseLength)
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
                )
              else
                TextField(
                  controller: _sizeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Size',
                    hintText: 'Cross-section, e.g. 3×6 or 1.5" OD',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_saving,
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
