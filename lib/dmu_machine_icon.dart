import 'package:flutter/material.dart';

/// Minimal DMU-style CNC front: outer body + inner pill window (no table/spindle).
class DmuMachineIcon extends StatelessWidget {
  const DmuMachineIcon({
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth,
  });

  final double size;
  final Color? color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.grey[700]!;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DmuMachinePainter(
          color: c,
          strokeWidth: strokeWidth ?? (size / 12).clamp(1.5, 2.2),
        ),
      ),
    );
  }
}

class _DmuMachinePainter extends CustomPainter {
  _DmuMachinePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final inset = strokeWidth / 2 + size.width * 0.06;
    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      Radius.circular(size.width * 0.18),
    );
    canvas.drawRRect(outer, paint);

    // Inner window — taller pill, centered with even side margin.
    final sidePad = size.width * 0.22;
    final topPad = size.height * 0.16;
    final bottomPad = size.height * 0.16;
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        sidePad,
        topPad,
        size.width - sidePad,
        size.height - bottomPad,
      ),
      Radius.circular(size.width * 0.14),
    );
    canvas.drawRRect(inner, paint);
  }

  @override
  bool shouldRepaint(covariant _DmuMachinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
