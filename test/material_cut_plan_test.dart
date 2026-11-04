import 'package:flutter_test/flutter_test.dart';
import 'package:cribhub/models.dart';

void main() {
  group('MaterialCutPlan', () {
    test('single cut with kerf', () {
      final p = MaterialCutPlan.compute(
        onShelfIn: 36,
        cutLengthIn: 12,
        quantity: 1,
        kerfIn: 0.125,
      );
      expect(p.fits, isTrue);
      expect(p.usedIn, closeTo(12.125, 1e-9));
      expect(p.remainingIn, closeTo(23.875, 1e-9));
    });

    test('multiple cuts add kerf each', () {
      final p = MaterialCutPlan.compute(
        onShelfIn: 36,
        cutLengthIn: 6,
        quantity: 4,
        kerfIn: 0.125,
      );
      expect(p.fits, isTrue);
      expect(p.kerfTotalIn, closeTo(0.5, 1e-9));
      expect(p.remainingIn, closeTo(11.5, 1e-9));
    });

    test('last cut to the end of the bar needs no kerf', () {
      final p = MaterialCutPlan.compute(
        onShelfIn: 24.125,
        cutLengthIn: 12,
        quantity: 2,
        kerfIn: 0.125,
      );
      expect(p.fits, isTrue);
      expect(p.remainingIn, 0);
      expect(p.kerfTotalIn, closeTo(0.125, 1e-9));
    });

    test('too long does not fit', () {
      final p = MaterialCutPlan.compute(
        onShelfIn: 10,
        cutLengthIn: 6,
        quantity: 2,
        kerfIn: 0.125,
      );
      expect(p.fits, isFalse);
    });

    test('no kerf uses whole piece exactly', () {
      final p = MaterialCutPlan.compute(
        onShelfIn: 18.25,
        cutLengthIn: 18.25,
        quantity: 1,
      );
      expect(p.fits, isTrue);
      expect(p.remainingIn, 0);
    });
  });

  group('parseLengthToInches', () {
    test('decimal inches', () {
      expect(parseLengthToInches('12.5'), 12.5);
      expect(parseLengthToInches(' .75 '), 0.75);
      expect(parseLengthToInches('6in'), 6);
      expect(parseLengthToInches('6"'), 6);
    });

    test('metric', () {
      expect(parseLengthToInches('254mm'), closeTo(10, 1e-9));
      expect(parseLengthToInches('2.54 cm'), closeTo(1, 1e-9));
    });

    test('rejects junk', () {
      expect(parseLengthToInches(''), isNull);
      expect(parseLengthToInches('abc'), isNull);
      expect(parseLengthToInches('12ft'), isNull);
    });
  });
}
