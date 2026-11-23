import 'package:flutter/material.dart';

import 'quote_cad_analysis.dart';

/// Preset part tints (mirrored for non-web API compatibility).
class CadPartColor {
  final String id;
  final String label;
  final Color color;

  const CadPartColor(this.id, this.label, this.color);
}

const kCadPartColors = <CadPartColor>[
  CadPartColor('charcoal', 'Charcoal', Color(0xFF3A3A3A)),
  CadPartColor('aluminum', 'Aluminum', Color(0xFF8B96A3)),
  CadPartColor('blue', 'Shop blue', Color(0xFF3D6FA8)),
];

/// Non-web placeholder — 3D CAD preview is web-only (model-viewer).
class CadGlbViewer extends StatelessWidget {
  final String meshUrl;
  final CadVec3? fixtureDown;
  final ValueChanged<CadVec3>? onFixtureFacePicked;

  const CadGlbViewer({
    super.key,
    required this.meshUrl,
    this.fixtureDown,
    this.onFixtureFacePicked,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '3D face pick is available in the web app',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
    );
  }
}
