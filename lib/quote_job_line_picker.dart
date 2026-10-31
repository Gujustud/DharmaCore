import 'package:flutter/material.dart';

/// Result of choosing which quote lines (and qtys) become job lines.
class QuoteJobLineSelection {
  QuoteJobLineSelection({
    required this.description,
    required this.quantity,
    this.quoteLineItemId,
    this.materialVendorId,
  });

  final String description;
  final num quantity;
  final String? quoteLineItemId;
  final String? materialVendorId;
}

/// Dialog: pick which quote lines to put on the new job (and override qty).
Future<List<QuoteJobLineSelection>?> showQuoteJobLinePicker({
  required BuildContext context,
  required List<Map<String, dynamic>> quoteLines,
}) async {
  if (quoteLines.isEmpty) {
    return <QuoteJobLineSelection>[];
  }

  return showDialog<List<QuoteJobLineSelection>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _QuoteJobLinePickerDialog(quoteLines: quoteLines),
  );
}

class _QuoteJobLinePickerDialog extends StatefulWidget {
  const _QuoteJobLinePickerDialog({required this.quoteLines});

  final List<Map<String, dynamic>> quoteLines;

  @override
  State<_QuoteJobLinePickerDialog> createState() =>
      _QuoteJobLinePickerDialogState();
}

class _QuoteJobLinePickerDialogState extends State<_QuoteJobLinePickerDialog> {
  late final List<bool> _selected;
  late final List<TextEditingController> _qtyControllers;

  @override
  void initState() {
    super.initState();
    _selected = List<bool>.filled(widget.quoteLines.length, true);
    _qtyControllers = [
      for (final line in widget.quoteLines)
        TextEditingController(text: '${line['part_quantity'] ?? 1}'),
    ];
  }

  @override
  void dispose() {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  String? _relationId(dynamic v) {
    if (v == null || v.toString().isEmpty) return null;
    if (v is String) return v;
    if (v is Map && v['id'] != null) return v['id'].toString();
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Parts for this job'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Uncheck any quoted parts that were not ordered. Adjust quantity if needed.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.quoteLines.length,
                itemBuilder: (context, i) {
                  final line = widget.quoteLines[i];
                  final part = '${line['part_number'] ?? ''}'.trim();
                  final label = part.isEmpty ? 'Unnamed Part' : part;
                  return CheckboxListTile(
                    value: _selected[i],
                    onChanged: (v) => setState(() => _selected[i] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(label),
                    secondary: SizedBox(
                      width: 72,
                      child: TextField(
                        controller: _qtyControllers[i],
                        enabled: _selected[i],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final out = <QuoteJobLineSelection>[];
            for (var i = 0; i < widget.quoteLines.length; i++) {
              if (!_selected[i]) continue;
              final line = widget.quoteLines[i];
              final part = '${line['part_number'] ?? ''}'.trim();
              final qty = num.tryParse(_qtyControllers[i].text.trim()) ??
                  (line['part_quantity'] as num?) ??
                  1;
              if (qty <= 0) continue;
              out.add(
                QuoteJobLineSelection(
                  description: part.isEmpty ? 'Unnamed Part' : part,
                  quantity: qty,
                  quoteLineItemId: line['id'] as String?,
                  materialVendorId: _relationId(line['material_vendor']),
                ),
              );
            }
            if (out.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select at least one part')),
              );
              return;
            }
            Navigator.pop(context, out);
          },
          child: const Text('Create job'),
        ),
      ],
    );
  }
}
