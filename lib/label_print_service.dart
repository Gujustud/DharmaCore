import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/painting.dart';
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
    final maxX = _contentMaxX(image);
    if (maxX < 0) return image;
    final newW = (maxX + rightPad + 1).clamp(1, image.width);
    if (newW >= image.width) return image;
    return img.copyCrop(image, x: 0, y: 0, width: newW, height: image.height);
  }

  /// Flatten anti-aliased grays to pure B/W for crisp TZe thermal output.
  static img.Image _toStrictBlackWhite(img.Image src, {int threshold = 160}) {
    final white = img.ColorRgba8(255, 255, 255, 255);
    final black = img.ColorRgba8(0, 0, 0, 255);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final lum = (p.r + p.g + p.b) / 3;
        src.setPixel(x, y, lum < threshold ? black : white);
      }
    }
    return src;
  }

  static TextPainter _labelTextPainter(
    String text, {
    required double fontSize,
    FontWeight weight = FontWeight.w700,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'NotoSans',
          fontWeight: weight,
          fontSize: fontSize,
          color: const Color(0xFF000000),
          height: 1.05,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 520);
    return painter;
  }

  static Future<Uint8List> _canvasLabelToPng({
    required int imageWidth,
    required int imageHeight,
    required void Function(Canvas canvas) paint,
    int rightPad = 12,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    paint(canvas);
    final picture = recorder.endRecording();
    final rendered =
        await picture.toImage(imageWidth, imageHeight);
    final byteData =
        await rendered.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    rendered.dispose();
    final raw = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final decoded = img.decodePng(raw);
    if (decoded == null) return raw;
    final bw = _toStrictBlackWhite(decoded);
    final cropped = _cropLabelToContent(bw, rightPad: rightPad);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  static void _paintQr(
    Canvas canvas, {
    required QrImage qrImage,
    required int moduleCount,
    required int modulePx,
    required double originX,
    required double originY,
  }) {
    final paint = Paint()..color = const Color(0xFF000000);
    for (var row = 0; row < moduleCount; row++) {
      for (var col = 0; col < moduleCount; col++) {
        if (!qrImage.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            originX + col * modulePx,
            originY + row * modulePx,
            modulePx.toDouble(),
            modulePx.toDouble(),
          ),
          paint,
        );
      }
    }
  }

  /// Generate label as PNG bytes: BIN + tool name + QR.
  /// Uses bundled NotoSans (not upscaled bitmap fonts).
  static Future<Uint8List> generateLabelImage({
    required String toolName,
    required String binCode,
    int? width,
    int? height,
  }) async {
    const leftMargin = 12.0;
    const rightMargin = 12;
    const qrVerticalMargin = 6;
    const gap = 8.0;
    const toolMaxCharsPerLine = 26;
    const binFontSize = 30.0;
    const nameFontSize = 26.0;

    final imageHeight = height ?? labelHeightPx;
    final qrMaxSide = imageHeight - 2 * qrVerticalMargin;

    final binNumber = binCode.contains('-')
        ? binCode.substring(binCode.lastIndexOf('-') + 1)
        : binCode;
    final qrData = '$toolName\nBIN: $binNumber';
    final qrCode = QrCode.fromData(
      data: qrData,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final qrImage = QrImage(qrCode);
    final qrModuleCount = qrImage.moduleCount;
    final qrModulePixel = (qrMaxSide / qrModuleCount).floor().clamp(1, 20);
    final qrSize = qrModuleCount * qrModulePixel;
    final qrY = (imageHeight - qrSize) / 2;

    final binLine = 'BIN: $binNumber';
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

    final binPainter = _labelTextPainter(binLine, fontSize: binFontSize);
    final namePainters = nameLines
        .map((l) => _labelTextPainter(l, fontSize: nameFontSize))
        .toList();

    var textCol = binPainter.width;
    for (final p in namePainters) {
      if (p.width > textCol) textCol = p.width;
    }

    final computedWidth =
        (leftMargin + textCol + gap + qrSize + rightMargin).ceil();
    final imageWidth = (width ?? computedWidth).clamp(0, maxLabelWidthPx);

    return _canvasLabelToPng(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      rightPad: rightMargin,
      paint: (canvas) {
        binPainter.paint(canvas, const Offset(leftMargin, 10));
        final nameBlockH =
            namePainters.fold<double>(0, (s, p) => s + p.height);
        var y = imageHeight - nameBlockH - 8;
        for (final p in namePainters) {
          p.paint(canvas, Offset(leftMargin, y));
          y += p.height;
        }
        _paintQr(
          canvas,
          qrImage: qrImage,
          moduleCount: qrModuleCount,
          modulePx: qrModulePixel,
          originX: leftMargin + textCol + gap,
          originY: qrY,
        );
      },
    );
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

  /// When true (via `--dart-define=BROTHER_SDK_PRINT=true`), Android uses the
  /// Brother Bluetooth SDK. Default is false: the SDK was hard-crashing the
  /// tablet APK (JNI abort inside printImage), so Android uses the system
  /// print sheet like web unless explicitly re-enabled after a verified fix.
  static const bool androidUseBrotherSdk = bool.fromEnvironment(
    'BROTHER_SDK_PRINT',
    defaultValue: false,
  );

  /// Send a label PNG to the printer (Android Bluetooth) or system print (web).
  ///
  /// Default Android path = system print dialog (pick PT-P910BT / 18mm).
  /// Optional Brother SDK path when [androidUseBrotherSdk] is true; on
  /// PlatformException falls back to system print.
  static Future<void> sendLabelPng(
    Uint8List pngBytes, {
    String jobName = 'label',
  }) async {
    if (kIsWeb || !androidUseBrotherSdk) {
      await _sendViaSystemPrint(pngBytes, jobName: jobName);
      return;
    }
    try {
      // Pass Uint8List directly (becomes byte[] on Android) — not List<int>.
      await _channel.invokeMethod<void>('printLabel', {
        'imageBytes': pngBytes,
      });
      return;
    } on MissingPluginException catch (e) {
      debugPrint('LabelPrintService: MissingPluginException, system print fallback: $e');
    } on PlatformException catch (e) {
      debugPrint(
        'LabelPrintService: Brother print failed (${e.code}: ${e.message}), '
        'system print fallback',
      );
    } catch (e) {
      debugPrint('LabelPrintService: Brother print error, system print fallback: $e');
    }
    await _sendViaSystemPrint(pngBytes, jobName: jobName);
  }

  static Future<void> _sendViaSystemPrint(
    Uint8List pngBytes, {
    required String jobName,
  }) async {
    final decoded = img.decodePng(pngBytes);
    final src = decoded ??
        img.Image(width: maxLabelWidthPx, height: labelHeightPx);
    final format = _labelPageFormat(src);
    await Printing.layoutPdf(
      name: jobName,
      format: format,
      onLayout: (_) => _pngAsLabelPdf(pngBytes),
    );
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
    final pngBytes =
        await generateLabelImage(toolName: toolName, binCode: binCode);
    await sendLabelPng(pngBytes, jobName: 'tool-$binCode');
  }

  /// QR payload for a material piece — stable id, not human length text.
  static String materialPieceQrPayload(String pieceId) => 'dharma://piece/$pieceId';

  /// Rightmost non-white x in [image], or -1 if blank.
  static int _contentMaxX(img.Image image) {
    var maxX = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = image.width - 1; x > maxX; x--) {
        final p = image.getPixel(x, y);
        if (p.r < 250 || p.g < 250 || p.b < 250) {
          maxX = x;
          break;
        }
      }
    }
    return maxX;
  }

  /// Material piece label + QR = piece id.
  /// Typical: identity / REM / P-code / optional LOT (after P).
  /// Identity + REM are bold; P-code + LOT are regular and one size smaller.
  static Future<Uint8List> generateMaterialLabelImage({
    required String line1,
    required String line2,
    String? heatLotLine,
    required String codeLine,
    required String pieceId,
    int? width,
    int? height,
  }) async {
    const leftMargin = 10.0;
    const rightMargin = 12;
    const qrVerticalMargin = 4;
    const primaryFontSize = 30.0;
    const metaFontSize = 24.0;
    const lineGap = 1.0;
    const maxChars = 34;

    final imageHeight = height ?? labelHeightPx;
    final qrMaxSide = imageHeight - 2 * qrVerticalMargin;

    final qrData = materialPieceQrPayload(pieceId);
    final qrCode = QrCode.fromData(
      data: qrData,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final qrImage = QrImage(qrCode);
    final qrModuleCount = qrImage.moduleCount;
    final qrModulePixel = (qrMaxSide / qrModuleCount).floor().clamp(1, 20);
    final qrSize = qrModuleCount * qrModulePixel;
    // Text must not crowd the QR: scanners need a blank quiet zone of a few
    // modules beside it, and the label reads better with clear separation.
    final gap = math.max(24.0, 3.0 * qrModulePixel);
    final qrY = (imageHeight - qrSize) / 2;

    String trimLine(String s) {
      final t = s.trim();
      if (t.length <= maxChars) return t;
      return '${t.substring(0, maxChars - 1)}…';
    }

    final primary = [
      trimLine(line1),
      trimLine(line2),
    ];
    final meta = <String>[
      trimLine(codeLine),
      if (heatLotLine != null && heatLotLine.trim().isNotEmpty)
        trimLine(heatLotLine),
    ];

    final painters = <TextPainter>[
      for (final l in primary)
        _labelTextPainter(
          l,
          fontSize: primaryFontSize,
          weight: FontWeight.w700,
        ),
      for (final l in meta)
        _labelTextPainter(
          l,
          fontSize: metaFontSize,
          weight: FontWeight.w400,
        ),
    ];

    var textCol = 40.0;
    var textBlockH = 0.0;
    for (var i = 0; i < painters.length; i++) {
      final p = painters[i];
      if (p.width > textCol) textCol = p.width;
      textBlockH += p.height;
      if (i < painters.length - 1) textBlockH += lineGap;
    }

    final computedWidth =
        (leftMargin + textCol + gap + qrSize + rightMargin).ceil();
    final imageWidth = (width ?? computedWidth).clamp(0, maxLabelWidthPx);
    // Vertically center the text block on the tape.
    final textTop =
        ((imageHeight - textBlockH) / 2).clamp(0.0, imageHeight.toDouble());

    return _canvasLabelToPng(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      rightPad: rightMargin,
      paint: (canvas) {
        var y = textTop;
        for (final p in painters) {
          p.paint(canvas, Offset(leftMargin, y));
          y += p.height + lineGap;
        }
        _paintQr(
          canvas,
          qrImage: qrImage,
          moduleCount: qrModuleCount,
          modulePx: qrModulePixel,
          originX: leftMargin + textCol + gap,
          originY: qrY,
        );
      },
    );
  }

  static Future<void> printMaterialLabel({
    required String line1,
    required String line2,
    String? heatLotLine,
    required String codeLine,
    required String pieceId,
    String jobName = 'material',
  }) async {
    final pngBytes = await generateMaterialLabelImage(
      line1: line1,
      line2: line2,
      heatLotLine: heatLotLine,
      codeLine: codeLine,
      pieceId: pieceId,
    );
    await sendLabelPng(pngBytes, jobName: jobName);
  }

  /// DEBUG: Export a sample label PNG to disk so it can be inspected without printing.
  /// Writes `sample_label.png` into the platform's documents directory and returns the full path.
  static Future<String> exportSampleLabelPng({
    required String toolName,
    required String binCode,
  }) async {
    final bytes =
        await generateLabelImage(toolName: toolName, binCode: binCode);
    final path = await _channel.invokeMethod<String>('exportLabelPng', {
      'imageBytes': bytes.toList(),
      'toolName': toolName,
      'binCode': binCode,
    });
    return path ?? '';
  }
}
