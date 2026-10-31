import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'models.dart';

/// Label printing for Brother PT-P710BT (18mm TZe tape).
/// Label shows: line 1 = tool name, line 2 = BIN: &lt;bin number&gt; only (e.g. A-A-1-4), QR encodes bin number.
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

  /// Pixels for 18mm tape width at 180 dpi (PT-P710BT). This is the max label height across the tape.
  static const int labelHeightPx = 127;

  /// Max label length along the tape at 180 dpi (3.1 inches) so labels fit in bins.
  static const int maxLabelWidthPx = 558; // 3.1" × 180 dpi

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

    // Height = full tape width in pixels (after 90° rotation this maps to 18mm).
    final imageHeight = height ?? labelHeightPx;
    // QR square uses max height minus margins.
    final qrMaxSide = imageHeight - 2 * qrVerticalMargin;

    // Bin number only (last segment of path, e.g. A-C-1-250 → 250) so label stays valid if bin is moved.
    final binNumber = binCode.contains('-')
        ? binCode.substring(binCode.lastIndexOf('-') + 1)
        : binCode;
    // QR encodes tool name + bin number so a scan shows both.
    final qrData = '$toolName\nBIN: $binNumber';
    final qrCode = QrCode(
      payload: QrPayload.fromString(qrData),
      errorCorrectLevel: QrErrorCorrectLevel.low,
    );
    final qrImage = QrImage(qrCode);
    final qrModuleCount = qrImage.moduleCount;
    final qrModulePixel = (qrMaxSide / qrModuleCount).floor().clamp(1, 20);
    final qrSize = qrModuleCount * qrModulePixel;
    final qrY = (imageHeight - qrSize) ~/ 2;

    // Width: text area + gap + QR + margins (length along tape), capped at 3.1".
    final computedWidth = leftMargin + 260 + 8 + qrSize + rightMargin;
    final imageWidth = (width ?? computedWidth).clamp(0, maxLabelWidthPx);

    final image = img.Image(width: imageWidth, height: imageHeight);
    final white = img.ColorRgba8(255, 255, 255, 255);
    final black = img.ColorRgba8(0, 0, 0, 255);
    img.fill(image, color: white);

    // Fonts: use arial24 for both, but scale BIN slightly larger via bitmap scaling.
    final binFont = img.arial24;
    final toolFont = img.arial24;
    const targetBinHeight = 32; // approx "30px" visual height after scaling
    const toolLineHeight = 28;
    const toolMaxCharsPerLine = 26;

    // BIN at top: bin number only (e.g. BIN: 250), scaled slightly larger.
    final binLine = 'BIN: $binNumber';
    const binY = 14; // a bit more breathing room from the top
    // Render BIN into a temporary image with the base font, then scale it UP.
    // Height of temp image (24) is smaller than targetBinHeight (32) so we enlarge.
    final binTemp = img.Image(width: imageWidth, height: 24);
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

    // QR code: sized to use max label height, right-aligned and vertically centered
    final qrX = imageWidth - qrSize - rightMargin;
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

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Send label image to the native side (Android: Brother SDK / stub).
  static Future<void> printLabel({
    required String toolName,
    required String binCode,
  }) async {
    final pngBytes = generateLabelImage(toolName: toolName, binCode: binCode);
    await _channel.invokeMethod<void>('printLabel', {'imageBytes': pngBytes.toList()});
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
    final qrCode = QrCode(
      payload: QrPayload.fromString(qrData),
      errorCorrectLevel: QrErrorCorrectLevel.low,
    );
    final qrImage = QrImage(qrCode);
    final qrModuleCount = qrImage.moduleCount;
    final qrModulePixel = (qrMaxSide / qrModuleCount).floor().clamp(1, 20);
    final qrSize = qrModuleCount * qrModulePixel;
    final qrY = (imageHeight - qrSize) ~/ 2;

    final computedWidth = leftMargin + 280 + 8 + qrSize + rightMargin;
    final imageWidth = (width ?? computedWidth).clamp(0, maxLabelWidthPx);

    final image = img.Image(width: imageWidth, height: imageHeight);
    final white = img.ColorRgba8(255, 255, 255, 255);
    final black = img.ColorRgba8(0, 0, 0, 255);
    img.fill(image, color: white);

    final font = img.arial24;
    const lineHeight = 28;
    const maxChars = 28;

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

    final qrX = imageWidth - qrSize - rightMargin;
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

    return Uint8List.fromList(img.encodePng(image));
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
    await _channel.invokeMethod<void>('printLabel', {
      'imageBytes': pngBytes.toList(),
    });
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
