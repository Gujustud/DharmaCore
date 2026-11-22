import 'package:flutter/material.dart';

/// Non-web placeholder — 3D CAD preview is web-only (model-viewer).
class CadGlbViewer extends StatelessWidget {
  final String meshUrl;
  final double height;

  const CadGlbViewer({
    super.key,
    required this.meshUrl,
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '3D preview is available in the web app',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
    );
  }
}
