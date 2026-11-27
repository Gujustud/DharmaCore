import 'models.dart';

/// Filament is tracked like inventory but is not a shop cutting tool.
bool isFilamentToolCategory(String? category) {
  final c = (category ?? '').trim().toLowerCase();
  if (c.isEmpty) return false;
  return c == '3d filament' ||
      c == '3dp filament' ||
      c.contains('filament');
}

/// Filament shelf destinations should not appear in Return / Transfer pickers.
bool isFilamentShelfLocation(Location location) {
  final n = location.name.trim().toLowerCase();
  return n.contains('filament');
}

/// True when no other location lists [location] as its parent.
bool isLeafLocation(Location location, List<Location> allLocations) {
  return !allLocations.any((other) => other.parentId == location.id);
}

/// Full path "Toolbox A - Drawer B - … - Bin 191".
String buildLocationPath(Location location, List<Location> allLocations) {
  final names = <String>[];
  var current = location;
  while (true) {
    names.insert(0, current.name);
    if (current.parentId == null || current.parentId!.isEmpty) break;
    try {
      current = allLocations.firstWhere((loc) => loc.id == current.parentId);
    } catch (_) {
      break;
    }
  }
  return names.join(' - ');
}

/// Home bin = the tool's toolbox [tool_locations] row (qty may be 0).
Location? findHomeBinLocation({
  required List<ToolLocation> toolLocations,
  required List<Location> allLocations,
  String? excludeLocationId,
}) {
  for (final tl in toolLocations) {
    if (excludeLocationId != null && tl.locationId == excludeLocationId) {
      continue;
    }
    Location? loc = tl.location;
    if (loc == null) {
      try {
        loc = allLocations.firstWhere((l) => l.id == tl.locationId);
      } catch (_) {
        loc = null;
      }
    }
    if (loc == null) continue;
    if (loc.type.trim().toLowerCase() == 'toolbox') {
      return loc;
    }
  }
  return null;
}

int toolLocationQuantity(dynamic quantityField) {
  if (quantityField is int) return quantityField;
  if (quantityField is num) return quantityField.toInt();
  return int.tryParse('$quantityField') ?? 0;
}
