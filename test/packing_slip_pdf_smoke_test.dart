import 'package:flutter_test/flutter_test.dart';
import 'package:cribhub/packing_slip_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('builds packing slip pdf', () async {
    final bytes = await buildPackingSlipPdf(PackingSlipData(
      packingSlipNumber: 'PS3000',
      shipToLines: const ['Heli-One Canada ULC', 'Richmond, BC'],
      date: DateTime(2026, 10, 6),
      purchaseOrder: 'S0390626',
      tracking: 'Fedex 123',
      lines: [
        PackingSlipLine(itemNumber: 1, quantity: 2, description: 'CAMERA MOUNT', packed: 2),
      ],
      packedBy: 'Amish',
      packedDate: DateTime(2026, 10, 6),
    ));
    expect(bytes.length, greaterThan(1000));
    // PDF magic
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
