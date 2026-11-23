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
}
