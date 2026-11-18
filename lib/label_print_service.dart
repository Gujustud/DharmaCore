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

/// Label printing for Brother PT-P910BT (18mm bin tags + 12mm / ~1/2" tool tags).
/// Bin labels: tool name + BIN + QR. Tool tags: name + LBH/TL blanks (or filled).
/// Material labels: code / identity / length, QR = piece id.
/// Android: Bluetooth via Brother SDK. Web/desktop Chrome: system print dialog.
class LabelPrintService {
  static const _channel = MethodChannel('com.sscadcam.dharmacore/label_printer');

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

  /// Pixels across 18mm tape for P910 (~360 dpi both axes / ~256 dots).
  static const int labelHeightPx = 256;

  /// Pixels across 12mm (~1/2") tape for P910 (~360 dpi).
  static const int labelHeightPx12mm = 170;

  /// P710/P715 18mm printable (128-pin head, high-res 180×360 → 112 dots).
  static const int labelHeightPxP710 = 112;

  /// P710/P715 12mm printable (~70 dots).
  static const int labelHeightPx12mmP710 = 70;

  /// Soft cap while laying out bitmaps (before PDF scales to [targetLabelLengthMm]).
  static const int maxLabelWidthPx = 1600;

  static const double tapeHeightMm18 = 18;
  static const double tapeHeightMm12 = 12;
  static const double _dpi = 360;

  /// Fixed along-tape length for the Windows / Chrome → Brother print path.
  ///
  /// Set the P910BT Printing Preferences **Length** once to this value (and
  /// paper **18 mm**). The PDF page is always this long; long stickers scale
  /// down to fit so the QR is never cropped by the driver Length setting.
  static const double targetLabelLengthMm = 70;

  /// Along-tape length for 12mm tool-tag stickers (Chrome → Brother).
  static const double targetToolTagLengthMm = 50;

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
    )..layout(maxWidth: maxLabelWidthPx.toDouble());
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

  /// Cross-tape pixel height for the preferred paired Brother (P710→112, P910→256).
  static Future<int> preferredLabelHeightPx({double tapeHeightMm = tapeHeightMm18}) async {
    final fallback =
        tapeHeightMm <= 12.5 ? labelHeightPx12mm : labelHeightPx;
    if (kIsWeb || !androidUseBrotherSdk) return fallback;
    try {
      final dots = await _channel.invokeMethod<int>('preferredTapeDots', {
        'tapeMm': tapeHeightMm.round(),
      });
      if (dots != null && dots >= 48 && dots <= 300) return dots;
    } catch (e) {
      debugPrint('preferredTapeDots: $e');
    }
    return fallback;
  }

  /// Generate label as PNG bytes: BIN + tool name + QR.
  /// Renders bundled NotoSans into a bitmap — Brother PT Bluetooth is raster-only
  /// (no live font/text commands for freeform labels).
  static Future<Uint8List> generateLabelImage({
    required String toolName,
    required String binCode,
    int? width,
    int? height,
  }) async {
    // TEXT top-aligned. QR vertically centered. Scale layout to [imageHeight]
    // so P710 (112) fills the tape instead of squashing a 256px P910 canvas.
    final imageHeight = height ?? labelHeightPx;
    final s = imageHeight / labelHeightPx; // 1.0 on P910, ~0.44 on P710
    final leftMargin = math.max(6.0, 14.0 * s);
    final rightMargin = math.max(6, (16 * s).round());
    final qrVerticalMargin = math.max(2, (4 * s).round());
    final gap = math.max(16.0, 72.0 * s);
    const toolMaxCharsPerLine = 26;
    // Fill most of the tape: ~40% / ~32% of cross-tape height.
    final binFontSize = math.max(22.0, imageHeight * 0.40);
    final nameFontSize = math.max(18.0, imageHeight * 0.32);
    final edgePad = math.max(2.0, imageHeight * 0.05);

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
    final qrModulePixel = (qrMaxSide / qrModuleCount).floor().clamp(1, 40);
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

    // One TextPainter so BIN + name are a single stacked paragraph.
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: binLine,
            style: TextStyle(
              fontFamily: 'NotoSans',
              fontWeight: FontWeight.w700,
              fontSize: binFontSize,
              color: const Color(0xFF000000),
              height: 1.1,
            ),
          ),
          for (final line in nameLines)
            TextSpan(
              text: '\n$line',
              style: TextStyle(
                fontFamily: 'NotoSans',
                fontWeight: FontWeight.w700,
                fontSize: nameFontSize,
                color: const Color(0xFF000000),
                height: 1.1,
              ),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1 + nameLines.length,
    )..layout(maxWidth: maxLabelWidthPx.toDouble());

    // Keep the QR fully on-canvas: text may ellipsis, never push QR off the right.
    final reserved = leftMargin + gap + qrSize + rightMargin;
    final textMax = math.max(40.0, maxLabelWidthPx - reserved);
    if (textPainter.width > textMax) {
      textPainter.layout(maxWidth: textMax);
    }
    final textCol = textPainter.width;
    final computedWidth =
        (leftMargin + textCol + gap + qrSize + rightMargin).ceil();
    final imageWidth = width ?? computedWidth;

    return _canvasLabelToPng(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      rightPad: rightMargin,
      paint: (canvas) {
        textPainter.paint(canvas, Offset(leftMargin, edgePad));
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

  /// PDF / driver page for [tapeHeightMm] (landscape: length × tape height).
  static PdfPageFormat _labelPageFormat({
    double tapeHeightMm = tapeHeightMm18,
    double lengthMm = targetLabelLengthMm,
  }) {
    return PdfPageFormat(
      lengthMm * PdfPageFormat.mm,
      tapeHeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );
  }

  /// When false (`--dart-define=BROTHER_SDK_PRINT=false`), Android skips the
  /// Brother Bluetooth SDK and uses the system print sheet (useful on web /
  /// Windows only — Android's print sheet cannot see a BT PT-P910BT).
  static const bool androidUseBrotherSdk = bool.fromEnvironment(
    'BROTHER_SDK_PRINT',
    defaultValue: true,
  );

  /// Send a label PNG to the printer (Android Bluetooth) or system print (web).
  ///
  /// [tapeHeightMm] selects Brother tape (18 = bin labels, 12 ≈ 1/2" tool tags).
  ///
  /// Android: one-tap via Brother SDK in a separate `:brother_print` process.
  /// PT-P910BT is Bluetooth-only — Android's system print dialog will **not**
  /// list it (Brother Print Service Plugin is Wi‑Fi models only), so we do
  /// **not** fall back to that dialog on Android; errors surface to the UI.
  static Future<void> sendLabelPng(
    Uint8List pngBytes, {
    String jobName = 'label',
    double tapeHeightMm = tapeHeightMm18,
    double lengthMm = targetLabelLengthMm,
  }) async {
    if (kIsWeb || !androidUseBrotherSdk) {
      await _sendViaSystemPrint(
        pngBytes,
        jobName: jobName,
        tapeHeightMm: tapeHeightMm,
        lengthMm: lengthMm,
      );
      return;
    }
    // Pass Uint8List directly (becomes byte[] on Android) — not List<int>.
    await _channel.invokeMethod<void>('printLabel', {
      'imageBytes': pngBytes,
      'tapeMm': tapeHeightMm.round(),
    });
  }

  static Future<void> _sendViaSystemPrint(
    Uint8List pngBytes, {
    required String jobName,
    double tapeHeightMm = tapeHeightMm18,
    double lengthMm = targetLabelLengthMm,
  }) async {
    final format = _labelPageFormat(
      tapeHeightMm: tapeHeightMm,
      lengthMm: lengthMm,
    );
    await Printing.layoutPdf(
      name: jobName,
      format: format,
      onLayout: (_) => _pngAsLabelPdf(
        pngBytes,
        tapeHeightMm: tapeHeightMm,
        lengthMm: lengthMm,
      ),
    );
  }

  /// Wrap PNG in a PDF for the browser → Brother print dialog.
  static Future<Uint8List> _pngAsLabelPdf(
    Uint8List pngBytes, {
    double tapeHeightMm = tapeHeightMm18,
    double lengthMm = targetLabelLengthMm,
  }) async {
    final page = _labelPageFormat(
      tapeHeightMm: tapeHeightMm,
      lengthMm: lengthMm,
    );
    final pageW = page.width;
    final pageH = page.height;
    final decoded = img.decodePng(pngBytes);
    final defaultH = tapeHeightMm <= 12.5 ? labelHeightPx12mm : labelHeightPx;
    final srcW = (decoded?.width ?? maxLabelWidthPx).toDouble();
    final srcH = (decoded?.height ?? defaultH).toDouble();
    final scale = math.min(pageW / srcW, pageH / srcH);
    final drawW = srcW * scale;
    final drawH = srcH * scale;

    final doc = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    doc.addPage(
      pw.Page(
        pageFormat: page,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Container(
          width: pageW,
          height: pageH,
          alignment: pw.Alignment.centerLeft,
          child: pw.SizedBox(
            width: drawW,
            height: drawH,
            child: pw.Image(image, fit: pw.BoxFit.fill),
          ),
        ),
      ),
    );
    return doc.save();
  }

  /// Send tool bin label (Android or web system print) — 18mm tape.
  static Future<void> printLabel({
    required String toolName,
    required String binCode,
  }) async {
    final height = await preferredLabelHeightPx(tapeHeightMm: tapeHeightMm18);
    final pngBytes = await generateLabelImage(
      toolName: toolName,
      binCode: binCode,
      height: height,
    );
    await sendLabelPng(pngBytes, jobName: 'tool-$binCode');
  }

  /// 12mm (~1/2") holder-tag sticker: tool name + LBH/TL lines.
  /// LBH = length below holder. Empty [lbh]/[tl] print as blanks for sharpie.
  static Future<Uint8List> generateToolTagLabelImage({
    required String toolName,
    String? lbh,
    String? tl,
    int? width,
    int? height,
  }) async {
    final imageHeight = height ?? labelHeightPx12mm;
    // Pack name + LBH + TL into nearly the full tape height; shrink if metrics overflow.
    const edgePad = 1.0;
    const lineGap = 0.0;
    final leftMargin = math.max(3.0, imageHeight * 0.05);
    final rightMargin = math.max(3, (imageHeight * 0.06).round());
    const maxNameChars = 28;
    final lbhVal = (lbh ?? '').trim();
    final tlVal = (tl ?? '').trim();
    final lbhLine = lbhVal.isEmpty ? 'LBH: ________' : 'LBH: $lbhVal';
    final tlLine = tlVal.isEmpty ? 'TL:  ________' : 'TL:  $tlVal';

    var name = toolName.trim();
    if (name.length > maxNameChars) {
      name = '${name.substring(0, maxNameChars - 1)}…';
    }

    final maxBlock = imageHeight - 2 * edgePad;
    // Moderate sizes — oversized type made stickers very long on P710.
    var nameFontSize = imageHeight * 0.34;
    var fieldFontSize = imageHeight * 0.24;
    late TextPainter namePainter;
    late TextPainter lbhPainter;
    late TextPainter tlPainter;
    var textBlockH = double.infinity;
    for (var attempt = 0; attempt < 12; attempt++) {
      namePainter = _labelTextPainter(
        name,
        fontSize: nameFontSize,
        weight: FontWeight.w700,
      );
      lbhPainter = _labelTextPainter(
        lbhLine,
        fontSize: fieldFontSize,
        weight: FontWeight.w700,
      );
      tlPainter = _labelTextPainter(
        tlLine,
        fontSize: fieldFontSize,
        weight: FontWeight.w700,
      );
      textBlockH = namePainter.height +
          lineGap +
          lbhPainter.height +
          lineGap +
          tlPainter.height;
      if (textBlockH <= maxBlock) break;
      final shrink = maxBlock / textBlockH;
      nameFontSize *= shrink * 0.98;
      fieldFontSize *= shrink * 0.98;
    }

    final textCol = math.max(
      namePainter.width,
      math.max(lbhPainter.width, tlPainter.width),
    );
    final computedWidth = (leftMargin + textCol + rightMargin).ceil();
    final imageWidth = width ?? computedWidth.clamp(80, maxLabelWidthPx);
    final textTop = ((imageHeight - textBlockH) / 2)
        .clamp(0.0, imageHeight.toDouble());

    return _canvasLabelToPng(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      rightPad: rightMargin,
      paint: (canvas) {
        var y = textTop;
        namePainter.paint(canvas, Offset(leftMargin, y));
        y += namePainter.height + lineGap;
        lbhPainter.paint(canvas, Offset(leftMargin, y));
        y += lbhPainter.height + lineGap;
        tlPainter.paint(canvas, Offset(leftMargin, y));
      },
    );
  }

  /// Print 12mm tool-tag sticker (holder tags). Optional [lbh]/[tl] fill the blanks.
  static Future<void> printToolTagLabel({
    required String toolName,
    String? lbh,
    String? tl,
  }) async {
    final height = await preferredLabelHeightPx(tapeHeightMm: tapeHeightMm12);
    final pngBytes = await generateToolTagLabelImage(
      toolName: toolName,
      lbh: lbh,
      tl: tl,
      height: height,
    );
    await sendLabelPng(
      pngBytes,
      jobName: 'tool-tag',
      tapeHeightMm: tapeHeightMm12,
      lengthMm: targetToolTagLengthMm,
    );
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
    const leftMargin = 12.0;
    const rightMargin = 14;
    const qrVerticalMargin = 2;
    const primaryFontSize = 66.0;
    const metaFontSize = 52.0;
    const lineGap = 2.0;
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
    final qrModulePixel = (qrMaxSide / qrModuleCount).floor().clamp(1, 40);
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

    // Reserve space for gap + QR so long identity lines never shove the QR
    // off the right edge of the bitmap (that showed up as a cut-off code).
    final reserved = leftMargin + gap + qrSize + rightMargin;
    final textMax = math.max(40.0, maxLabelWidthPx - reserved);

    final painters = <TextPainter>[
      for (final l in primary)
        _labelTextPainter(
          l,
          fontSize: primaryFontSize,
          weight: FontWeight.w700,
        )..layout(maxWidth: textMax),
      for (final l in meta)
        _labelTextPainter(
          l,
          fontSize: metaFontSize,
          weight: FontWeight.w400,
        )..layout(maxWidth: textMax),
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
    final imageWidth = width ?? computedWidth;
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
