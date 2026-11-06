import 'package:flutter/material.dart';

/// Corner radius for tip-profile filter buttons (matches brand dropdown).
const double kToolFilterIconRadius = 8;

/// Maps Cutting Tools type/style names to tip-profile icons.
///
/// Style icons (Flat/Ball/…) from https://cnctools.dev/tagger (owner-approved).
/// CR → Radius Mill. Special → Probe.
///
/// Type icons (Endmills/Drills/Threading) in [assets/icons/tool_types]
/// (Endmills = Flat tip; Threading = zigzag A).
///
/// Style reference: https://label.alch.shop/
class ToolStyleIcons {
  ToolStyleIcons._();

  static const String styleAssetDir = 'assets/icons/tool_styles';
  static const String typeAssetDir = 'assets/icons/tool_types';

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

  static const Map<String, String> typeAssets = {
    'endmills': '$typeAssetDir/endmills.png',
    'endmill': '$typeAssetDir/endmills.png',
    'drills': '$typeAssetDir/drills.png',
    'drill': '$typeAssetDir/drills.png',
    'threading': '$typeAssetDir/threading.png',
    'thread': '$typeAssetDir/threading.png',
  };

  /// Preferred display order for top-level types (Endmills → Drills → Threading).
  static const List<String> typeOrder = [
    'endmills',
    'endmill',
    'drills',
    'drill',
    'threading',
    'thread',
  ];

  /// Preferred display order for Endmill styles.
  static const List<String> endmillStyleOrder = [
    'flat',
    'cr',
    'ball',
    'chamfer',
    'tslot',
    't-slot',
    't_slot',
    'special',
  ];

  static const double iconButtonSize = 40;

  static String normalize(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

  static String? assetForStyle(String style) => endmillAssets[normalize(style)];

  static bool hasIcon(String style) => assetForStyle(style) != null;

  static String? assetForType(String type) => typeAssets[normalize(type)];

  static bool hasTypeIcon(String type) => assetForType(type) != null;

  /// Sort [items] by [preferred] keys (normalized); unknowns keep relative alpha order at end.
  static List<String> sortByPreferred(
    Iterable<String> items,
    List<String> preferred,
  ) {
    final preferredNorm = [
      for (final p in preferred) normalize(p),
    ];
    final list = items.toList();
    list.sort((a, b) {
      final ai = preferredNorm.indexOf(normalize(a));
      final bi = preferredNorm.indexOf(normalize(b));
      if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return list;
  }
}

/// Square tip-profile filter button (white fill, dark stroke icons).
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
    final radius = BorderRadius.circular(kToolFilterIconRadius);

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
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: ring, width: selected ? 2.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            width: ToolStyleIcons.iconButtonSize,
            height: ToolStyleIcons.iconButtonSize,
            child: child,
          ),
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

/// Compact text chip for "All" and styles/types without an icon.
///
/// When [square] is true (e.g. the All control), uses the same 40×40 footprint
/// as [ToolStyleIconButton].
class ToolFilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool square;

  const ToolFilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.square = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(kToolFilterIconRadius);
    final text = Text(
      label,
      style: TextStyle(
        fontSize: square ? 12 : 13,
        fontWeight: FontWeight.w600,
        color: selected ? scheme.onPrimary : scheme.onSurface,
        height: 1,
      ),
    );
    return Tooltip(
      message: label,
      child: Material(
        color: selected ? scheme.primary : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: square
              ? SizedBox(
                  width: ToolStyleIcons.iconButtonSize,
                  height: ToolStyleIcons.iconButtonSize,
                  child: Center(child: text),
                )
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: text,
                ),
        ),
      ),
    );
  }
}
