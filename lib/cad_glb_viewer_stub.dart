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
  CadPartColor('aluminum', 'Aluminum', Color(0xFF8B96A3)),
  CadPartColor('blue', 'Shop blue', Color(0xFF3D6FA8)),
  CadPartColor('charcoal', 'Charcoal', Color(0xFF3A3A3A)),
];

/// Non-web placeholder — 3D CAD preview is web-only (model-viewer).
class CadGlbViewer extends StatelessWidget {
  final String meshUrl;
  final CadVec3? fixtureDown;

  const CadGlbViewer({
    super.key,
    required this.meshUrl,
    this.fixtureDown,
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
        fixtureDown == null
            ? '3D preview is available in the web app'
            : '3D preview (fixture ${cadDirectionLabel(fixtureDown!)})',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
    );
  }
}
