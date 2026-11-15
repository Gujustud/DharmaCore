import 'package:cribhub/app_date_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAppDate', () {
    test('parses common US and ISO forms', () {
      expect(parseAppDate('11/14/2026'), DateTime(2026, 11, 14));
      expect(parseAppDate('2026-11-14'), DateTime(2026, 11, 14));
      expect(parseAppDate('Nov 14, 2026'), DateTime(2026, 11, 14));
      expect(parseAppDate('11-14-2026'), DateTime(2026, 11, 14));
    });

    test('round-trips display format', () {
      final d = DateTime(2026, 11, 14);
      expect(parseAppDate(formatAppDate(d)), d);
      expect(formatAppDateIso(d), '2026-11-14');
    });
  });
}
