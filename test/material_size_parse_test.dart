import 'package:flutter_test/flutter_test.dart';
import 'package:cribhub/material_size_parse.dart';

void main() {
  group('barLengthFromSizeLabel', () {
    test('reads trailing length from 3-part size', () {
      expect(barLengthFromSizeLabel('3×6×23'), 23);
      expect(barLengthFromSizeLabel('3x6x60'), 60);
    });

    test('null for cross-section only', () {
      expect(barLengthFromSizeLabel('3×6'), isNull);
      expect(barLengthFromSizeLabel('1.5" OD'), isNull);
    });
  });

  group('stripTrailingLengthFromSizeLabel', () {
    test('strips trailing bar length', () {
      expect(stripTrailingLengthFromSizeLabel('3×6×23'), '3×6');
      expect(stripTrailingLengthFromSizeLabel('1 x 4 x 144'), '1 x 4');
    });

    test('null when nothing to strip', () {
      expect(stripTrailingLengthFromSizeLabel('3×6'), isNull);
    });
  });

  group('catalogSizeLabel', () {
    test('plate composes section × length into catalog size', () {
      expect(
        catalogSizeLabel(
          sectionSize: '1.5×3',
          lengthIn: 3.5,
          form: 'plate',
        ),
        '1.5×3×3.5',
      );
    });

    test('flat keeps section only', () {
      expect(
        catalogSizeLabel(
          sectionSize: '3×6',
          lengthIn: 60,
          form: 'flat',
        ),
        '3×6',
      );
    });
  });
}
