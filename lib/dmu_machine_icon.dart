import 'package:flutter/material.dart';

/// Minimal DMU-style CNC front: body + window + right pendant (design C).
/// Drawn large in its box so it fills the shortcut chip.
class DmuMachineIcon extends StatelessWidget {
  const DmuMachineIcon({
    super.key,
    this.size = 26,
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
          strokeWidth: strokeWidth ?? (size / 10).clamp(1.8, 2.6),
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
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Leave room for the pendant on the right; otherwise fill the square.
    final pad = strokeWidth / 2 + 0.5;
    final pendantW = size.width * 0.22;
    final bodyRight = size.width - pad - pendantW;

    final outer = RRect.fromRectAndRadius(
      Rect.fromLTRB(pad, pad, bodyRight, size.height - pad),
      Radius.circular(size.width * 0.12),
    );
    canvas.drawRRect(outer, paint);

    // Inner window — thin frame so the glyph stays bold at small size.
    final frame = size.width * 0.14;
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        pad + frame,
        pad + frame,
        bodyRight - frame,
        size.height - pad - frame,
      ),
      Radius.circular(size.width * 0.08),
    );
    canvas.drawRRect(inner, paint);

    // Pendant: monitor + slanted deck on the right.
    final midY = size.height * 0.42;
    final monLeft = bodyRight - strokeWidth * 0.3;
    final monRight = size.width - pad;
    final monTop = midY - size.height * 0.10;
    final monBot = midY + size.height * 0.06;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(monLeft, monTop, monRight, monBot),
        Radius.circular(size.width * 0.04),
      ),
      paint,
    );

    final deckTop = monBot + strokeWidth * 0.4;
    final deckBot = deckTop + size.height * 0.10;
    final deck = Path()
      ..moveTo(monLeft + size.width * 0.02, deckTop)
      ..lineTo(monRight, deckTop)
      ..lineTo(monRight - size.width * 0.04, deckBot)
      ..lineTo(monLeft + size.width * 0.04, deckBot)
      ..close();
    canvas.drawPath(deck, paint);
  }

  @override
  bool shouldRepaint(covariant _DmuMachinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
