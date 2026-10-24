import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Company block printed on every packing slip (matches Libre Writer templates).
class PackingSlipCompany {
  static const name = 'SS CAD CAM Inc.';
  static const addressLines = [
    '106 – 1101 Commercial Place',
    'Squamish, BC, V8B 1B5',
  ];
  static const phone = 'T: 604.277.4077';
  static const email = 'E: amish@sscadcam.com';
}

class PackingSlipLine {
  PackingSlipLine({
    required this.itemNumber,
    required this.quantity,
    required this.description,
    required this.packed,
  });

  final int itemNumber;
  final num quantity;
  final String description;
  final num packed;
}

class PackingSlipData {
  PackingSlipData({
    required this.packingSlipNumber,
    required this.shipToLines,
    required this.date,
    required this.purchaseOrder,
    required this.tracking,
    required this.lines,
    required this.packedBy,
    required this.packedDate,
  });

  final String packingSlipNumber;
  final List<String> shipToLines;
  final DateTime date;
  final String purchaseOrder;
  final String tracking;
  final List<PackingSlipLine> lines;
  final String packedBy;
  final DateTime packedDate;
}

Future<Uint8List> buildPackingSlipPdf(PackingSlipData data) async {
  final logoBytes = await rootBundle.load('assets/ss_cadcam_logo.png');
  final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
  final dateFmt = DateFormat('MMM d yyyy');
  // Bundled Unicode fonts (part numbers often use en-dashes).
  final baseData = await rootBundle.load('fonts/NotoSans-Regular.ttf');
  final boldData = await rootBundle.load('fonts/NotoSans-Bold.ttf');
  final base = pw.Font.ttf(baseData);
  final bold = pw.Font.ttf(boldData);
  final theme = pw.ThemeData.withFont(base: base, bold: bold);

  final doc = pw.Document(
    title: data.packingSlipNumber,
    author: PackingSlipCompany.name,
    theme: theme,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(0.5 * PdfPageFormat.inch),
      theme: theme,
      build: (context) => [
        _header(logo, data),
        pw.SizedBox(height: 16),
        _metaRow(data, dateFmt),
        pw.SizedBox(height: 16),
        _itemsTable(data),
      ],
      footer: (context) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _packedByFooter(data, dateFmt),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'PAGE: ${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _header(pw.MemoryImage logo, PackingSlipData data) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Packing Slip',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              data.packingSlipNumber,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Ship To:',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            ...data.shipToLines.map(
              (line) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 1),
                child: pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 16),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Image(logo, width: 220, height: 55, fit: pw.BoxFit.contain),
            pw.SizedBox(height: 8),
            // Logo artwork already includes the company name.
            ...PackingSlipCompany.addressLines.map(
              (l) => pw.Text(
                l,
                style: const pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Text(
              PackingSlipCompany.phone,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.right,
            ),
            pw.Text(
              PackingSlipCompany.email,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.right,
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _metaRow(PackingSlipData data, DateFormat dateFmt) {
  pw.Widget metaCell(String label, String value) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      );

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey700, width: 0.6),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        metaCell('DATE', dateFmt.format(data.date)),
        metaCell(
          'PURCHASE ORDER',
          data.purchaseOrder.isEmpty ? '-' : data.purchaseOrder,
        ),
        metaCell('TRACKING', data.tracking.isEmpty ? '-' : data.tracking),
      ],
    ),
  );
}

pw.Widget _itemsTable(PackingSlipData data) {
  final headers = ['ITEM', 'QTY', 'DESCRIPTION', 'PACKED'];
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: data.lines
        .map(
          (l) => [
            '${l.itemNumber}',
            '${l.quantity}',
            l.description,
            '${l.packed}',
          ],
        )
        .toList(),
    headerStyle: pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 9,
      color: PdfColors.black,
    ),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellAlignments: {
      0: pw.Alignment.center,
      1: pw.Alignment.center,
      2: pw.Alignment.centerLeft,
      3: pw.Alignment.center,
    },
    columnWidths: {
      0: const pw.FixedColumnWidth(40),
      1: const pw.FixedColumnWidth(40),
      2: const pw.FlexColumnWidth(4),
      3: const pw.FixedColumnWidth(50),
    },
    border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.4),
    headerHeight: 22,
    cellHeight: 20,
  );
}

pw.Widget _packedByFooter(PackingSlipData data, DateFormat dateFmt) {
  pw.Widget signedBlock(String value, String label) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: const pw.TextStyle(fontSize: 11),
            textAlign: pw.TextAlign.center,
          ),
          pw.Container(
            width: 180,
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(width: 0.7)),
            ),
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      signedBlock(
        data.packedBy.isEmpty ? '-' : data.packedBy,
        'Packed by',
      ),
      pw.SizedBox(width: 24),
      signedBlock(dateFmt.format(data.packedDate), 'Date'),
    ],
  );
}
