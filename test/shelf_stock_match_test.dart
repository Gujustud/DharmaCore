import 'package:cribhub/shelf_stock_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stockCoversNeed', () {
    test('rejects undersize cross-section', () {
      expect(stockCoversNeed([2, 4], [1, 4, 144]), isFalse);
      expect(stockCoversNeed([2, 4], [1.75, 4, 144]), isFalse);
    });

    test('accepts equal or larger after rotation', () {
      expect(stockCoversNeed([2, 4], [2, 4, 144]), isTrue);
      expect(stockCoversNeed([2, 4], [4, 2, 144]), isTrue);
      expect(stockCoversNeed([2, 4], [3, 4, 144]), isTrue);
      expect(stockCoversNeed([2, 4], [4, 3]), isTrue);
    });
  });

  group('scoreSizeMatch', () {
    test('scores exact above larger, undersize as zero', () {
      expect(scoreSizeMatch([2, 4], [2, 4, 144]), 1000);
      expect(scoreSizeMatch([2, 4], [3, 4, 144]), greaterThanOrEqualTo(500));
      expect(scoreSizeMatch([2, 4], [3, 4, 144]), lessThan(1000));
      expect(scoreSizeMatch([2, 4], [1, 4, 144]), 0);
      expect(scoreSizeMatch([2, 4], [1.75, 4, 144]), 0);
    });
  });

  group('remCoversLength', () {
    test('reads cut length from 1×4×20 style sizes', () {
      expect(neededLengthFromSize([1, 4, 20]), 20);
      expect(neededLengthFromSize([1, 4]), isNull);
    });

    test('rejects REM shorter than needed cut', () {
      expect(remCoversLength(17.75, 20), isFalse);
      expect(remCoversLength(101, 20), isTrue);
      expect(remCoversLength(17.75, null), isTrue);
    });
  });

  group('remNeededForCuts', () {
    test('scales with pieces and includes kerf', () {
      final one = remNeededForCuts(cutLengthIn: 5, pieces: 1)!;
      final five = remNeededForCuts(cutLengthIn: 5, pieces: 5)!;
      expect(one, greaterThanOrEqualTo(5));
      expect(five, greaterThan(one));
      expect(five, closeTo(5 * 5 + 5 * 0.125, 0.01));
      expect(remCoversLength(17.75, five), isFalse);
      expect(remCoversLength(101, five), isTrue);
    });
  });
}
