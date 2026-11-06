import 'package:flutter/material.dart';

/// Maps Cutting Tools type/style names to tip-profile icons.
///
/// Style icons (Flat/Ball/…) currently from https://cnctools.dev/tagger
/// (owner-approved). CR → Radius Mill. Special → Probe.
///
/// Type icons (Endmills/Drills/Threading) are original drafts in
/// [assets/icons/tool_types] (Endmills reuses Flat; Threading = zigzag A).
///
/// Style reference for future hand-drawn icons:
/// https://label.alch.shop/ (ModuBOX Label Generator — clean small glyph buttons).
class ToolStyleIcons {
  ToolStyleIcons._();

  static const String styleAssetDir = 'assets/icons/tool_styles';
  static const String typeAssetDir = 'assets/icons/tool_types';

  /// Normalized endmill style key → asset path.
  static const Map<String, String> endmillAssets = {
    'flat': '$styleAssetDir/flat.png',
    'ball': '$styleAssetDir/ball.png',
    'cr': '$styleAssetDir/cr.png',
    'chamfer': '$styleAssetDir/chamfer.png',
    'tslot': '$styleAssetDir/tslot.png',
    't-slot': '$styleAssetDir/tslot.png',
    't_slot': '$styleAssetDir/tslot.png',
    'special': '$styleAssetDir/special.png',
  };

  /// Normalized tool-type key → asset path.
  static const Map<String, String> typeAssets = {
    'endmills': '$typeAssetDir/endmills.png',
    'endmill': '$typeAssetDir/endmills.png',
    'drills': '$typeAssetDir/drills.png',
    'drill': '$typeAssetDir/drills.png',
    'threading': '$typeAssetDir/threading.png',
    'thread': '$typeAssetDir/threading.png',
  };

  static String normalize(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

  static String? assetForStyle(String style) => endmillAssets[normalize(style)];

  static bool hasIcon(String style) => assetForStyle(style) != null;

  static String? assetForType(String type) => typeAssets[normalize(type)];

  static bool hasTypeIcon(String type) => assetForType(type) != null;
}

/// Circular tip-profile button (white fill, dark stroke icons).
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
    final ring = selected ? scheme.primary : scheme.outlineVariant;

    final child = assetPath != null
        ? Image.asset(
            assetPath!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) =>
                fallback ?? _letterFallback(label, scheme),
          )
        : ColoredBox(
            color: Colors.white,
            child: fallback ?? _letterFallback(label, scheme),
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
            color: Colors.white,
            border: Border.all(color: ring, width: selected ? 2.5 : 1),
          ),
          child: ClipOval(child: child),
        ),
      ),
    );
  }

  Widget _letterFallback(String label, ColorScheme scheme) {
    final letter = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          color: scheme.onSurface,
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
        color: selected ? scheme.primary : Colors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
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
