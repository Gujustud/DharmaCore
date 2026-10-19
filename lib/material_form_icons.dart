import 'package:flutter/material.dart';

/// Canonical material form keys (stored on `materials.form`).
const List<String> kMaterialForms = [
  'flat',
  'bar',
  'plate',
  'sheet',
  'tube',
  'other',
];

String materialFormLabel(String form) {
  switch (form) {
    case 'flat':
      return 'Flat';
    case 'bar':
    case 'rod':
      // Stored key stays `bar` for round stock; UI says Rod (McMaster wording).
      return 'Rod';
    case 'plate':
      return 'Plate';
    case 'sheet':
      return 'Sheet';
    case 'tube':
      return 'Tube';
    case 'other':
      return 'Other';
    default:
      return form;
  }
}

/// Normalize UI/alias form keys to the catalog value stored in PocketBase.
String canonicalMaterialForm(String form) {
  final f = form.trim().toLowerCase();
  if (f == 'rod') return 'bar';
  return f;
}

/// Compact row of flat 2D form icons for picking [value].
class MaterialFormIconRow extends StatelessWidget {
  const MaterialFormIconRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wrap = constraints.maxWidth < 360;
        final children = [
          for (final form in kMaterialForms)
            _FormIconButton(
              form: form,
              selected: value == form,
              enabled: enabled,
              onTap: () => onChanged(form),
            ),
        ];
        if (wrap) {
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: children,
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

class _FormIconButton extends StatelessWidget {
  const _FormIconButton({
    required this.form,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String form;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final bg = selected
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final border = selected
        ? scheme.secondary
        : scheme.outlineVariant;

    return Tooltip(
      message: materialFormLabel(form),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: selected ? 1.5 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CustomPaint(
                    painter: MaterialFormIconPainter(
                      form: form,
                      color: enabled ? fg : fg.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  materialFormLabel(form),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: enabled ? fg : fg.withValues(alpha: 0.4),
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat silhouette painter for a material form key.
class MaterialFormIconPainter extends CustomPainter {
  MaterialFormIconPainter({required this.form, required this.color});

  final String form;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final c = Offset(size.width / 2, size.height / 2);
    final s = size.shortestSide;

    switch (canonicalMaterialForm(form)) {
      case 'flat':
        canvas.drawRect(
          Rect.fromCenter(center: c, width: s * 0.72, height: s * 0.28),
          paint,
        );
      case 'bar':
        canvas.drawCircle(c, s * 0.32, paint);
      case 'plate':
        canvas.drawRect(
          Rect.fromCenter(center: c, width: s * 0.78, height: s * 0.42),
          paint,
        );
      case 'sheet':
        canvas.drawRect(
          Rect.fromCenter(center: c, width: s * 0.82, height: s * 0.16),
          paint,
        );
      case 'tube':
        canvas.drawCircle(c, s * 0.34, stroke);
        canvas.drawCircle(c, s * 0.16, stroke);
      case 'other':
      default:
        final r = s * 0.07;
        canvas.drawCircle(Offset(c.dx - s * 0.22, c.dy), r, paint);
        canvas.drawCircle(c, r, paint);
        canvas.drawCircle(Offset(c.dx + s * 0.22, c.dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MaterialFormIconPainter oldDelegate) {
    return oldDelegate.form != form || oldDelegate.color != color;
  }
}
