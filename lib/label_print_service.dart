import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart';

import 'models.dart';

/// Label printing for Brother PT-P910BT (18mm TZe; P710BT still supported on Android).
/// Tool labels: line 1 = tool name, line 2 = BIN, QR = tool + BIN.
/// Material labels: code / identity / length, QR = piece id.
/// Android: Bluetooth via Brother SDK. Web/desktop Chrome: system print dialog.
class LabelPrintService {
  static const _channel = MethodChannel('com.cribhub/label_printer');

  /// Build short bin code from location path (bin number only, e.g. A-A-1-4).
  /// [pathNames] = ordered list from root to leaf, e.g. ["Toolbox A", "Drawer A", "Row 1", "Bin 4"].
  static String pathToBinCode(List<String> pathNames) {
    if (pathNames.isEmpty) return '';
    return pathNames.map((name) {
      final parts = name.trim().split(RegExp(r'\s+'));
      return parts.isEmpty ? name : parts.last;
    }).join('-');
  }

  /// Build path names (root → leaf) for a [location] using [allLocations].
  static List<String> getPathNames(Location location, List<Location> allLocations) {
    final names = <String>[];
    Location? current = location;
    while (current != null) {
      names.insert(0, current.name);
      if (current.parentId == null || current.parentId!.isEmpty) break;
      try {
        current = allLocations.firstWhere((l) => l.id == current!.parentId);
      } catch (_) {
        break;
      }
    }
    return names;
  }

  /// Generate bin code for a bin-type [location] (bin number only for label).
  static String getBinCodeForLocation(Location location, List<Location> allLocations) {
    return pathToBinCode(getPathNames(location, allLocations));
  }

  /// Pixels for 18mm tape width at 180 dpi. Max label height across the tape.
  static const int labelHeightPx = 127;

  /// Max label length along the tape at 180 dpi (3.1 inches) so labels fit in bins.
  static const int maxLabelWidthPx = 558; // 3.1" × 180 dpi

  static const double _tapeHeightMm = 18;
  static const double _dpi = 180;

  /// Trim trailing blank tape: keep ink + [rightPad] px only.
  static img.Image _cropLabelToContent(img.Image image, {int rightPad = 16}) {
    var maxX = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = image.width - 1; x > maxX; x--) {
        final p = image.getPixel(x, y);
        if (p.r < 250 || p.g < 250 || p.b < 250) {
          maxX = x;
          break;
        }
      }
    }
    final newW = (maxX + rightPad + 1).clamp(1, image.width);
    if (newW >= image.width) return image;
    return img.copyCrop(image, x: 0, y: 0, width: newW, height: image.height);
  }

  /// Generate label as PNG bytes: line 1 = [toolName], line 2 = BIN: [binCode], QR = tool name + BIN.
  /// Canvas height = full 18mm (labelHeightPx); QR uses that height; width = length along tape.
  static Uint8List generateLabelImage({
    required String toolName,
    required String binCode,
    int? width,
    int? height,
  }) {
    const leftMargin = 14;
    const rightMargin = 16;
    const qrVerticalMargin = 6;

    // Height = full 18mm tape width in pixels.
    final imageHeight = height ?? labelHeightPx;
    // QR square uses max height minus margins.
    final qrMaxSide = imageHeight - 2 * qrVerticalMargin;

    // Bin number only (last segment of path, e.g. A-C-1-250 → 250) so label stays valid if bin is moved.
    final binNumber = binCode.contains('-')
        ? binCode.substring(binCode.lastIndexOf('-') + 1)
        : binCode;
    // QR encodes tool name + bin number so a scan shows both.
    final qrData = '$toolName\nBIN: $binNumber';
    // qr ^3 API (pdf/barcode pins qr <4).
    final qrCode = QrCode.fromData(
      data: qrData,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final qrImage = QrImage(qrCode);
    final qrModuleCount = qrImage.moduleCount;
    final qrModulePixel = (qrMaxSide / qrModuleCount).floor().clamp(1, 20);
    final qrSize = qrModuleCount * qrModulePixel;
    final qrY = (imageHeight - qrSize) ~/ 2;

    // Fonts: use arial24 for both, but scale BIN slightly larger via bitmap scaling.
    final binFont = img.arial24;
    final toolFont = img.arial24;
    const targetBinHeight = 32; // approx "30px" visual height after scaling
    const toolLineHeight = 28;
    const toolMaxCharsPerLine = 26;
    // ~14px/char for arial24; BIN is scaled ~32/24 so slightly wider.
    const pxPerChar = 14;

    // BIN at top: bin number only (e.g. BIN: 250), scaled slightly larger.
    final binLine = 'BIN: $binNumber';

    // Tool name near bottom: wrap to 2 lines if too long (split at last space).
    final nameLines = <String>[];
    if (toolName.length <= toolMaxCharsPerLine) {
      nameLines.add(toolName);
    } else {
      final first = toolName.substring(0, toolMaxCharsPerLine + 1);
      final lastSpace = first.lastIndexOf(' ');
      final splitAt = (lastSpace > 0) ? lastSpace : toolMaxCharsPerLine;
      nameLines.add(toolName.substring(0, splitAt).trim());
      nameLines.add(toolName.substring(splitAt).trim());
      if (nameLines.last.length > toolMaxCharsPerLine) {
        nameLines[nameLines.length - 1] =
            '${nameLines.last.substring(0, toolMaxCharsPerLine - 3)}...';
      }
    }

    var textCol = (binLine.length * pxPerChar * targetBinHeight / 24).ceil();
    for (final line in nameLines) {
      final w = line.length * pxPerChar;
      if (w > textCol) textCol = w;
    }
    textCol = textCol.clamp(80, 260);

    // Width: text + gap + QR + margins (length along tape), capped at 3.1".
    const gap = 8;
    final computedWidth = leftMargin + textCol + gap + qrSize + rightMargin;
    final imageWidth = (width ?? computedWidth).clamp(0, maxLabelWidthPx);

    final image = img.Image(width: imageWidth, height: imageHeight);
    final white = img.ColorRgba8(255, 255, 255, 255);
    final black = img.ColorRgba8(0, 0, 0, 255);
    img.fill(image, color: white);

    const binY = 14; // a bit more breathing room from the top
    // Render BIN into a temporary image with the base font, then scale it UP.
    // Height of temp image (24) is smaller than targetBinHeight (32) so we enlarge.
    final binTemp = img.Image(width: textCol + 8, height: 24);
    img.fill(binTemp, color: white);
    img.drawString(
      binTemp,
      binLine,
      font: binFont,
      x: 0,
      y: 0,
      color: black,
    );
    final binScaled = img.copyResize(binTemp, height: targetBinHeight);
    img.compositeImage(
      image,
      binScaled,
      dstX: leftMargin,
      dstY: binY,
    );

    final toolBlockHeight = nameLines.length * toolLineHeight;
    final toolStartY = imageHeight - toolBlockHeight - 8; // 8px bottom margin
    for (var i = 0; i < nameLines.length; i++) {
      img.drawString(
        image,
        nameLines[i],
        font: toolFont,
        x: leftMargin,
        y: toolStartY + i * toolLineHeight,
        color: black,
      );
    }

    // QR immediately after the text column (saves blank tape).
    final qrX = leftMargin + textCol + gap;
    for (var row = 0; row < qrModuleCount; row++) {
      for (var col = 0; col < qrModuleCount; col++) {
        if (qrImage.isDark(row, col)) {
          for (var dy = 0; dy < qrModulePixel; dy++) {
            for (var dx = 0; dx < qrModulePixel; dx++) {
              final x = qrX + col * qrModulePixel + dx;
              final y = qrY + row * qrModulePixel + dy;
              if (x < imageWidth && y < imageHeight) {
                image.setPixel(x, y, black);
              }
            }
          }
        }
      }
    }

    final cropped = _cropLabelToContent(image, rightPad: rightMargin);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  /// Along-tape length in mm for a label bitmap (x = length, y = 18mm).
  static double _labelLengthMm(img.Image src) {
    // Hug content; keep a small floor so drivers accept the page.
    return (src.width / _dpi * 25.4).clamp(28.0, 90.0);
  }

  static PdfPageFormat _labelPageFormat(img.Image src) {
    final lengthMm = _labelLengthMm(src);
    // Landscape: width = length along tape, height = 18mm tape width.
    // Windows Brother prefs must also be 18mm (not 36mm); set Length short there too.
    return PdfPageFormat(
      lengthMm * PdfPageFormat.mm,
      _tapeHeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );
  }

  /// Send a label PNG to the printer (Android Bluetooth) or system print (web).
  static Future<void> sendLabelPng(
    Uint8List pngBytes, {
    String jobName = 'label',
  }) async {
    if (kIsWeb) {
      final decoded = img.decodePng(pngBytes);
      final src = decoded ??
          img.Image(width: maxLabelWidthPx, height: labelHeightPx);
      final format = _labelPageFormat(src);
      await Printing.layoutPdf(
        name: jobName,
        format: format,
        onLayout: (_) => _pngAsLabelPdf(pngBytes),
      );
      return;
    }
    await _channel.invokeMethod<void>('printLabel', {
      'imageBytes': pngBytes.toList(),
    });
  }

  /// Wrap PNG in a PDF for the browser → Brother print dialog.
  ///
  /// Page is landscape: along-tape length × 18mm (no rotate). That matches how
  /// the bitmap is drawn and keeps Chrome from stretching a tall strip onto a
  /// long fixed-length roll. Pick **18 mm** paper and a short **Length** in
  /// Brother printing preferences (driver default 100mm wastes tape).
  static Future<Uint8List> _pngAsLabelPdf(Uint8List pngBytes) async {
    final decoded = img.decodePng(pngBytes);
    final src = decoded ??
        img.Image(width: maxLabelWidthPx, height: labelHeightPx);
    // Always size to the label; ignore letter/A4 if the dialog resets format.
    final page = _labelPageFormat(src);
    final pageW = page.width;
    final pageH = page.height;

    final doc = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    doc.addPage(
      pw.Page(
        pageFormat: page,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.SizedBox(
          width: pageW,
          height: pageH,
          child: pw.Image(image, fit: pw.BoxFit.fill),
        ),
      ),
    );
    return doc.save();
  }

  /// Send tool bin label (Android or web system print).
  static Future<void> printLabel({
    required String toolName,
    required String binCode,
  }) async {
    final pngBytes = generateLabelImage(toolName: toolName, binCode: binCode);
    await sendLabelPng(pngBytes, jobName: 'tool-$binCode');
  }

  /// QR payload for a material piece — stable id, not human length text.
  static String materialPieceQrPayload(String pieceId) => 'dharma://piece/$pieceId';

  /// Material piece label: code + grade/form/size + length, QR = piece id.
  static Uint8List generateMaterialLabelImage({
    required String labelCode,
    required String identityLine,
    required String lengthLine,
    required String pieceId,
    int? width,
    int? height,
  }) {
    const leftMargin = 14;
    const rightMargin = 16;
    const qrVerticalMargin = 6;

    final imageHeight = height ?? labelHeightPx;
    final qrMaxSide = imageHeight - 2 * qrVerticalMargin;

    final qrData = materialPieceQrPayload(pieceId);
    // qr ^3 API (pdf/barcode pins qr <4).
    final qrCode = QrCode.fromData(
      data: qrData,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final qrImage = QrImage(qrCode);
    final qrModuleCount = qrImage.moduleCount;
    final qrModulePixel = (qrMaxSide / qrModuleCount).floor().clamp(1, 20);
    final qrSize = qrModuleCount * qrModulePixel;
    final qrY = (imageHeight - qrSize) ~/ 2;

    final font = img.arial24;
    const lineHeight = 28;
    const maxChars = 28;
    const pxPerChar = 14;
    const gap = 8;

    String trimLine(String s) {
      final t = s.trim();
      if (t.length <= maxChars) return t;
      return '${t.substring(0, maxChars - 1)}…';
    }

    final lines = <String>[
      trimLine(labelCode),
      trimLine(identityLine),
      trimLine(lengthLine),
    ];

    var textCol = 80;
    for (final line in lines) {
      final w = line.length * pxPerChar;
      if (w > textCol) textCol = w;
    }
    textCol = textCol.clamp(80, 260);

    final computedWidth = leftMargin + textCol + gap + qrSize + rightMargin;
    final imageWidth = (width ?? computedWidth).clamp(0, maxLabelWidthPx);

    final image = img.Image(width: imageWidth, height: imageHeight);
    final white = img.ColorRgba8(255, 255, 255, 255);
    final black = img.ColorRgba8(0, 0, 0, 255);
    img.fill(image, color: white);

    var y = 10;
    for (final line in lines) {
      img.drawString(
        image,
        line,
        font: font,
        x: leftMargin,
        y: y,
        color: black,
      );
      y += lineHeight;
    }

    // QR immediately after the text column (saves blank tape).
    final qrX = leftMargin + textCol + gap;
    for (var row = 0; row < qrModuleCount; row++) {
      for (var col = 0; col < qrModuleCount; col++) {
        if (qrImage.isDark(row, col)) {
          for (var dy = 0; dy < qrModulePixel; dy++) {
            for (var dx = 0; dx < qrModulePixel; dx++) {
              final x = qrX + col * qrModulePixel + dx;
              final py = qrY + row * qrModulePixel + dy;
              if (x < imageWidth && py < imageHeight) {
                image.setPixel(x, py, black);
              }
            }
          }
        }
      }
    }

    final cropped = _cropLabelToContent(image, rightPad: rightMargin);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  static Future<void> printMaterialLabel({
    required String labelCode,
    required String identityLine,
    required String lengthLine,
    required String pieceId,
  }) async {
    final pngBytes = generateMaterialLabelImage(
      labelCode: labelCode,
      identityLine: identityLine,
      lengthLine: lengthLine,
      pieceId: pieceId,
    );
    await sendLabelPng(pngBytes, jobName: 'material-$labelCode');
  }

  /// DEBUG: Export a sample label PNG to disk so it can be inspected without printing.
  /// Writes `sample_label.png` into the platform's documents directory and returns the full path.
  static Future<String> exportSampleLabelPng({
    required String toolName,
    required String binCode,
  }) async {
    final bytes = generateLabelImage(toolName: toolName, binCode: binCode);
    // Use a platform channel on Android/iOS, or write directly on desktop/web via dart:io.
    // For simplicity here we just reuse the same MethodChannel with a debug method.
    final path = await _channel.invokeMethod<String>('exportLabelPng', {
      'imageBytes': bytes.toList(),
      'toolName': toolName,
      'binCode': binCode,
    });
    return path ?? '';
  }
}
