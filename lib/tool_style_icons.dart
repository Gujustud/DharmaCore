import 'package:flutter/material.dart';

/// Maps Cutting Tools style names (2nd subcategory segment) to cnctools tip icons.
///
/// Icons sourced from https://cnctools.dev/tagger (owner-approved).
/// CR → Radius Mill. Special → Probe.
class ToolStyleIcons {
  ToolStyleIcons._();

  static const String assetDir = 'assets/icons/tool_styles';

  /// Normalized style key → asset path.
  static const Map<String, String> endmillAssets = {
    'flat': '$assetDir/flat.png',
    'ball': '$assetDir/ball.png',
    'cr': '$assetDir/cr.png',
    'chamfer': '$assetDir/chamfer.png',
    'tslot': '$assetDir/tslot.png',
    't-slot': '$assetDir/tslot.png',
    't_slot': '$assetDir/tslot.png',
    'special': '$assetDir/special.png',
  };

  static String normalize(String style) =>
      style.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String? assetForStyle(String style) {
    final key = normalize(style);
    return endmillAssets[key];
  }

  static bool hasIcon(String style) => assetForStyle(style) != null;
}

/// Circular tip-profile button matching the cnctools Tagger strip.
class ToolStyleIconButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? assetPath;
  final Widget? fallback;

  const ToolStyleIconButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.assetPath,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = selected ? scheme.primary : Colors.transparent;

    final child = assetPath != null
        ? Image.asset(
            assetPath!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) =>
                fallback ?? _letterFallback(label),
          )
        : ColoredBox(
            color: const Color(0xFF1C1F24),
            child: fallback ?? _letterFallback(label),
          );

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 2.5),
          ),
          child: ClipOval(child: child),
        ),
      ),
    );
  }

  Widget _letterFallback(String label) {
    final letter = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: const TextStyle(
          color: Color(0xFFE8E8E8),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

/// Compact text chip used for tool types (Endmills / Drills / Threading)
/// and for styles that do not yet have an icon.
class ToolFilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ToolFilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
