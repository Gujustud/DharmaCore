import 'package:cribhub/quote_cad_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fixture-down stock sorts ascending like AABB', () {
    final analysis = <String, dynamic>{
      'bbox_in': {'x': 2.0, 'y': 4.0, 'z': 1.0},
      'bbox_lower_mm': {'x': 0.0, 'y': 0.0, 'z': 0.0},
      // 2" x 4" x 1" box in mm
      'bbox_upper_mm': {
        'x': 2.0 * 25.4,
        'y': 4.0 * 25.4,
        'z': 1.0 * 25.4,
      },
    };

    // Bottom = −Y → thickness along Y = 4", but output is still small→large.
    final withBottom = Map<String, dynamic>.from(analysis)
      ..['bottom_direction'] = {'x': 0.0, 'y': -1.0, 'z': 0.0};
    final oriented = cadStockSuggestOf(withBottom)!;
    // pad 0.1 → ceil 0.5: 1.5, 2.5, 4.5 → "1.5 x 2.5 x 4.5" (not 4.5 x 1.5 x 2.5)
    expect(oriented, '1.5 x 2.5 x 4.5');

    final aabb = cadStockSuggestOf(analysis)!;
    expect(aabb, '1.5 x 2.5 x 4.5');
  });

  test('stock size key ignores spaces and × glyph', () {
    expect(cadStockSizeKey('5 × 1 × 7.5'), cadStockSizeKey('5 x 1 x 7.5'));
  });

  test('direction labels snap to cardinal axes', () {
    expect(cadDirectionLabel(const CadVec3(0, 0, -1)), '−Z');
    expect(cadDirectionLabel(const CadVec3(0, 1, 0)), '+Y');
  });

  test('bottom direction round-trips through analysis map', () {
    final n = const CadVec3(0.0, -0.66, -0.75).normalized();
    final analysis = <String, dynamic>{
      'status': 'ok',
      'bottom_direction': n.toJson(),
      'bbox_lower_mm': {'x': 0, 'y': 0, 'z': 0},
      'bbox_upper_mm': {'x': 25.4, 'y': 25.4, 'z': 25.4},
      'bbox_in': {'x': 1, 'y': 1, 'z': 1},
    };
    final got = cadBottomDirectionOf(analysis)!;
    expect(got.nearlyEquals(n), isTrue);
    expect(cadStockSuggestOf(analysis), isNotNull);
  });

  test('stock box maps smallest dim onto smallest part axis (mm mesh)', () {
    final analysis = <String, dynamic>{
      'bbox_in': {'x': 7.244, 'y': 4.606, 'z': 0.492},
      'bbox_lower_mm': {'x': 0.0, 'y': 0.0, 'z': 0.0},
      'bbox_upper_mm': {
        'x': 7.244 * 25.4,
        'y': 4.606 * 25.4,
        'z': 0.492 * 25.4,
      },
    };
    final fromMm = cadStockBoxMeters(
      analysis: analysis,
      stockSizeLabel: '1 x 5 x 7.5',
    )!;
    // Absolute mm path: Z=0.5", Y=2.5", X=3.75" in mm halves
    expect(fromMm.halfExtentsM.z, closeTo(0.5 * 25.4 * 0.5, 1e-6));
    expect(fromMm.halfExtentsM.y, closeTo(2.5 * 25.4 * 0.5, 1e-6));
    expect(fromMm.halfExtentsM.x, closeTo(3.75 * 25.4 * 0.5, 1e-6));

    // Live mesh path: scale from getDimensions-style size (mm).
    final meshSize = CadVec3(
      7.244 * 25.4,
      4.606 * 25.4,
      0.492 * 25.4,
    );
    final fromMesh = cadStockBoxFromMesh(
      meshCenter: CadVec3(
        meshSize.x * 0.5,
        meshSize.y * 0.5,
        meshSize.z * 0.5,
      ),
      meshSize: meshSize,
      analysis: analysis,
      stockSizeLabel: '1 x 5 x 7.5',
    )!;
    expect(fromMesh.halfExtentsM.z, closeTo(0.5 * 25.4 * 0.5, 1e-6));
    expect(fromMesh.halfExtentsM.y, closeTo(2.5 * 25.4 * 0.5, 1e-6));
    expect(fromMesh.halfExtentsM.x, closeTo(3.75 * 25.4 * 0.5, 1e-6));
    expect(fromMesh.corners, hasLength(8));
  });

  test('feature type entries sort by count', () {
    final entries = cadFeatureTypeEntries({
      'feature_types': {'pocket': 2, 'hole': 40, 'chamfer': 5},
    });
    expect(entries.map((e) => e.key).toList(), ['hole', 'chamfer', 'pocket']);
    expect(entries.first.value, 40);
  });
}
