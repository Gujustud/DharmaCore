// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:math' as math;
import 'dart:svg' as svg;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'quote_cad_analysis.dart';

var _cadViewerCounter = 0;
var _hotspotCssInjected = false;

/// Preset part tints for the Toolpath GLB (baseColorFactor).
class CadPartColor {
  final String id;
  final String label;
  final Color color;

  const CadPartColor(this.id, this.label, this.color);
}

const kCadPartColors = <CadPartColor>[
  CadPartColor('charcoal', 'Charcoal', Color(0xFF3A3A3A)),
  CadPartColor('aluminum', 'Aluminum', Color(0xFF8B96A3)),
  CadPartColor('blue', 'Shop blue', Color(0xFF3D6FA8)),
];

/// Yellow stock blank outline (shop accent).
const _kStockStroke = '#F9A825';

const _kStockEdges = <(int, int)>[
  (0, 1),
  (1, 2),
  (2, 3),
  (3, 0),
  (4, 5),
  (5, 6),
  (6, 7),
  (7, 4),
  (0, 4),
  (1, 5),
  (2, 6),
  (3, 7),
];

void _ensureHotspotCss() {
  if (_hotspotCssInjected) return;
  _hotspotCssInjected = true;
  html.document.head!.append(html.StyleElement()
    ..text = '''
.cad-fixture-hotspot {
  display: block;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  border: 2px solid #fff;
  background: #e65100;
  box-shadow: 0 0 0 2px rgba(230,81,0,0.45), 0 1px 4px rgba(0,0,0,0.35);
  transform: translate(-50%, -50%);
  pointer-events: none;
}
.cad-pick-hint {
  position: absolute;
  left: 8px;
  top: 8px;
  padding: 4px 8px;
  border-radius: 4px;
  background: rgba(0,0,0,0.55);
  color: #fff;
  font: 11px/1.3 system-ui, sans-serif;
  pointer-events: none;
  z-index: 2;
}
.cad-stock-corner {
  width: 0;
  height: 0;
  margin: 0;
  padding: 0;
  border: 0;
  opacity: 0;
  pointer-events: none;
}
.cad-stock-svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
  z-index: 1;
  overflow: visible;
}
.cad-stock-svg line {
  stroke: $_kStockStroke;
  stroke-width: 1.75;
  stroke-linecap: round;
}
''');
}

/// Web 3D CAD preview via `<model-viewer>`.
///
/// Click a face (without dragging) to set fixture-down from the surface
/// normal. Optional yellow stock wire box follows [stockSizeLabel].
class CadGlbViewer extends StatefulWidget {
  final String meshUrl;

  /// When set, face pick marker stays; picking calls [onFixtureFacePicked].
  final CadVec3? fixtureDown;

  /// Called with the outward face normal (table-down when that face is bottom).
  final ValueChanged<CadVec3>? onFixtureFacePicked;

  /// Live stock blank label (`1 x 5 x 7.5`) — drives the yellow outline.
  final String? stockSizeLabel;

  /// Analysis JSON (bbox corners) for centering the stock box.
  final Map<String, dynamic>? analysis;

  const CadGlbViewer({
    super.key,
    required this.meshUrl,
    this.fixtureDown,
    this.onFixtureFacePicked,
    this.stockSizeLabel,
    this.analysis,
  });

  @override
  State<CadGlbViewer> createState() => _CadGlbViewerState();
}

class _CadGlbViewerState extends State<CadGlbViewer> {
  static const _studioBg = Color(0xFFF4F4F4);

  late final String _viewType;
  html.DivElement? _host;
  html.Element? _viewer;
  html.Element? _hotspot;
  html.Element? _hint;
  svg.SvgSvgElement? _stockSvg;
  final List<html.Element> _stockCorners = [];
  final List<svg.LineElement> _stockLines = [];
  String? _blobUrl;
  String? _loadError;
  bool _loading = true;
  int _loadGen = 0;
  String _colorId = kCadPartColors.first.id;
  bool _xray = false;
  bool _showStockOutline = true;
  num? _ptrDownX;
  num? _ptrDownY;
  StreamSubscription<html.MouseEvent>? _downSub;
  StreamSubscription<html.MouseEvent>? _clickSub;
  StreamSubscription<html.Event>? _cameraSub;
  StreamSubscription<html.Event>? _loadSub;

  @override
  void initState() {
    super.initState();
    _ensureHotspotCss();
    _viewType = 'cad-glb-viewer-${_cadViewerCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final host = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'relative'
        ..style.backgroundColor = '#f4f4f4';
      _host = host;
      return host;
    });
    scheduleMicrotask(_reloadMesh);
  }

  @override
  void dispose() {
    _downSub?.cancel();
    _clickSub?.cancel();
    _cameraSub?.cancel();
    _loadSub?.cancel();
    _revokeBlob();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CadGlbViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meshUrl != widget.meshUrl) {
      _reloadMesh();
      return;
    }
    if (oldWidget.fixtureDown != null && widget.fixtureDown == null) {
      _hotspot?.remove();
      _hotspot = null;
      _hint?.text = 'Click a face for fixture bottom (drag to orbit)';
    }
    final stockChanged =
        oldWidget.stockSizeLabel != widget.stockSizeLabel ||
            oldWidget.analysis != widget.analysis;
    if (stockChanged) {
      _syncStockOutline();
    }
  }

  void _revokeBlob() {
    final url = _blobUrl;
    _blobUrl = null;
    if (url != null) {
      html.Url.revokeObjectUrl(url);
    }
  }

  CadPartColor get _selectedColor =>
      kCadPartColors.firstWhere((c) => c.id == _colorId,
          orElse: () => kCadPartColors.first);

  Future<void> _reloadMesh() async {
    final gen = ++_loadGen;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final resp = await http
          .get(Uri.parse(widget.meshUrl))
          .timeout(const Duration(seconds: 360));
      if (!mounted || gen != _loadGen) return;

      if (resp.statusCode != 200) {
        final detail = _errorDetail(resp.bodyBytes, resp.statusCode);
        setState(() {
          _loading = false;
          _loadError = detail;
        });
        return;
      }

      final bytes = resp.bodyBytes;
      if (bytes.length < 12 ||
          bytes[0] != 0x67 ||
          bytes[1] != 0x6c ||
          bytes[2] != 0x54 ||
          bytes[3] != 0x46) {
        setState(() {
          _loading = false;
          _loadError =
              'Mesh proxy returned non-GLB data (${bytes.length} bytes)';
        });
        return;
      }

      _revokeBlob();
      final blob = html.Blob([bytes], 'model/gltf-binary');
      final url = html.Url.createObjectUrlFromBlob(blob);
      _blobUrl = url;

      await _mountViewer(url);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _loadError = null;
      });
    } on TimeoutException {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _loadError = 'Timed out loading 3D mesh (Toolpath still working?)';
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load 3D mesh: $e';
      });
    }
  }

  String _errorDetail(Uint8List body, int status) {
    final text = utf8.decode(body, allowMalformed: true).trim();
    if (text.isEmpty) return 'Mesh HTTP $status';
    try {
      final decoded = json.decode(text);
      if (decoded is Map) {
        final detail =
            decoded['detail'] ?? decoded['error'] ?? decoded['message'];
        if (detail != null && '$detail'.trim().isNotEmpty) {
          return 'Mesh HTTP $status: $detail';
        }
      }
    } catch (_) {}
    final short = text.length > 180 ? '${text.substring(0, 180)}…' : text;
    return 'Mesh HTTP $status: $short';
  }

  Future<void> _mountViewer(String blobUrl) async {
    try {
      final custom = html.window.customElements;
      if (custom != null) {
        await custom
            .whenDefined('model-viewer')
            .timeout(const Duration(seconds: 20));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError =
            'model-viewer failed to load (CDN blocked?). Hard-refresh and retry.';
      });
      return;
    }

    for (var i = 0; i < 40 && _host == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    final host = _host;
    if (host == null || !mounted) return;

    _downSub?.cancel();
    _clickSub?.cancel();
    _cameraSub?.cancel();
    _loadSub?.cancel();
    _hotspot = null;
    _stockCorners.clear();
    _stockLines.clear();
    _stockSvg = null;

    final el = html.Element.tag('model-viewer')
      ..setAttribute('src', blobUrl)
      ..setAttribute('camera-controls', '')
      ..setAttribute('disable-tap', '')
      ..setAttribute('touch-action', 'pan-y')
      ..setAttribute('interaction-prompt', 'none')
      ..setAttribute('shadow-intensity', '0.85')
      ..setAttribute('exposure', '1.1')
      ..setAttribute('environment-image', 'neutral')
      ..setAttribute('orientation', '0deg 0deg 0deg')
      ..setAttribute('camera-orbit', '35deg 65deg 105%')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.backgroundColor = '#f4f4f4'
      ..style.cursor = 'crosshair';

    final hint = html.DivElement()
      ..className = 'cad-pick-hint'
      ..text = 'Click a face for fixture bottom (drag to orbit)';
    _hint = hint;

    final stockSvg = svg.SvgSvgElement()..classes.add('cad-stock-svg');
    _stockSvg = stockSvg;

    final completer = Completer<void>();
    _loadSub = el.on['load'].listen((_) {
      _applyPartAppearance(el);
      _syncStockOutline();
      if (!completer.isCompleted) completer.complete();
    });
    el.on['error'].listen((_) {
      if (!completer.isCompleted) {
        completer.completeError('model-viewer failed to render GLB');
      }
    });

    _downSub = el.onMouseDown.listen((e) {
      _ptrDownX = e.client.x;
      _ptrDownY = e.client.y;
    });
    _clickSub = el.onClick.listen(_onViewerClick);
    _cameraSub = el.on['camera-change'].listen((_) => _redrawStockSvg());

    host.children.clear();
    host.append(el);
    host.append(stockSvg);
    host.append(hint);
    _viewer = el;

    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _applyPartAppearance(el);
      _syncStockOutline();
    }
  }

  void _onViewerClick(html.MouseEvent e) {
    final el = _viewer;
    if (el == null || widget.onFixtureFacePicked == null) return;

    if (_ptrDownX != null && _ptrDownY != null) {
      final dx = e.client.x - _ptrDownX!;
      final dy = e.client.y - _ptrDownY!;
      if (dx * dx + dy * dy > 36) return;
    }

    final clientX = e.client.x.toDouble();
    final clientY = e.client.y.toDouble();

    dynamic hit;
    try {
      hit = js_util.callMethod(
        el,
        'positionAndNormalFromPoint',
        [clientX, clientY],
      );
    } catch (_) {
      _hint?.text = 'Face pick failed — try again';
      return;
    }
    if (hit == null) {
      _hint?.text = 'Missed the part — click a face (drag to orbit)';
      return;
    }

    final normalObj = js_util.getProperty(hit, 'normal');
    final positionObj = js_util.getProperty(hit, 'position');
    if (normalObj == null) {
      _hint?.text = 'No face normal at that point — try again';
      return;
    }

    final nx = _numProp(normalObj, 'x');
    final ny = _numProp(normalObj, 'y');
    final nz = _numProp(normalObj, 'z');
    if (nx == null || ny == null || nz == null) return;

    final normal = CadVec3(nx, ny, nz).normalized();
    if (normal.length < 1e-6) return;

    if (positionObj != null) {
      _setHotspotFromHit(el, positionObj, normalObj, normal);
    }

    _hint?.text = 'Fixture face set — Apply stock when ready';

    if (mounted) setState(() {});
    widget.onFixtureFacePicked!(normal);
  }

  double? _numProp(dynamic obj, String name) {
    try {
      final v = js_util.getProperty(obj, name);
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    } catch (_) {
      return null;
    }
  }

  void _setHotspotFromHit(
    html.Element viewer,
    dynamic positionObj,
    dynamic normalObj,
    CadVec3 normalFallback,
  ) {
    _hotspot?.remove();
    final spot = html.DivElement()
      ..className = 'cad-fixture-hotspot'
      ..slot = 'hotspot-fixture-bottom';

    String? posStr;
    String? nrmStr;
    try {
      posStr = js_util.callMethod(positionObj, 'toString', [])?.toString();
    } catch (_) {}
    try {
      nrmStr = js_util.callMethod(normalObj, 'toString', [])?.toString();
    } catch (_) {}

    if (posStr == null || posStr.isEmpty) {
      final px = _numProp(positionObj, 'x');
      final py = _numProp(positionObj, 'y');
      final pz = _numProp(positionObj, 'z');
      if (px == null || py == null || pz == null) return;
      posStr = '${px}m ${py}m ${pz}m';
    }
    if (nrmStr == null || nrmStr.isEmpty) {
      nrmStr =
          '${normalFallback.x}m ${normalFallback.y}m ${normalFallback.z}m';
    }

    spot.setAttribute('data-position', posStr);
    spot.setAttribute('data-normal', nrmStr);
    viewer.append(spot);
    _hotspot = spot;
  }

  void _clearStockOutlineDom() {
    for (final c in _stockCorners) {
      c.remove();
    }
    _stockCorners.clear();
    for (final line in _stockLines) {
      line.remove();
    }
    _stockLines.clear();
    _stockSvg?.style.display = 'none';
  }

  void _syncStockOutline() {
    final el = _viewer;
    final stockSvg = _stockSvg;
    if (el == null || stockSvg == null) return;

    if (!_showStockOutline) {
      _clearStockOutlineDom();
      return;
    }

    final box = cadStockBoxMeters(
      analysis: widget.analysis,
      stockSizeLabel: widget.stockSizeLabel ?? '',
    );
    if (box == null) {
      _clearStockOutlineDom();
      return;
    }

    if (_stockCorners.length != 8) {
      _clearStockOutlineDom();
      for (var i = 0; i < 8; i++) {
        final corner = html.DivElement()
          ..className = 'cad-stock-corner'
          ..slot = 'hotspot-stock-$i';
        el.append(corner);
        _stockCorners.add(corner);
      }
      for (final _ in _kStockEdges) {
        final line = svg.LineElement()
          ..setAttribute('x1', '0')
          ..setAttribute('y1', '0')
          ..setAttribute('x2', '0')
          ..setAttribute('y2', '0');
        stockSvg.append(line);
        _stockLines.add(line);
      }
    }

    final corners = box.corners;
    for (var i = 0; i < 8; i++) {
      final p = corners[i];
      _stockCorners[i].setAttribute(
        'data-position',
        '${p.x}m ${p.y}m ${p.z}m',
      );
      // Face outward-ish so hotspots stay queryable.
      _stockCorners[i].setAttribute('data-normal', '0m 1m 0m');
    }

    stockSvg.style.display = '';
    // Let model-viewer place hotspots, then project to SVG.
    scheduleMicrotask(_redrawStockSvg);
    Future<void>.delayed(const Duration(milliseconds: 50), _redrawStockSvg);
  }

  void _redrawStockSvg() {
    final el = _viewer;
    final stockSvg = _stockSvg;
    if (el == null ||
        stockSvg == null ||
        !_showStockOutline ||
        _stockCorners.length != 8 ||
        _stockLines.length != _kStockEdges.length) {
      return;
    }

    final rect = el.getBoundingClientRect();
    final w = rect.width;
    final h = rect.height;
    if (w <= 0 || h <= 0) return;
    stockSvg.setAttribute('viewBox', '0 0 $w $h');
    stockSvg.style.width = '${w}px';
    stockSvg.style.height = '${h}px';

    final pts = <math.Point<double>?>[];
    for (var i = 0; i < 8; i++) {
      pts.add(_hotspotCanvasPoint(el, 'hotspot-stock-$i', w, h));
    }

    for (var e = 0; e < _kStockEdges.length; e++) {
      final (a, b) = _kStockEdges[e];
      final pa = pts[a];
      final pb = pts[b];
      final line = _stockLines[e];
      if (pa == null || pb == null) {
        line.style.display = 'none';
        continue;
      }
      line.style.display = '';
      line.setAttribute('x1', pa.x.toStringAsFixed(1));
      line.setAttribute('y1', pa.y.toStringAsFixed(1));
      line.setAttribute('x2', pb.x.toStringAsFixed(1));
      line.setAttribute('y2', pb.y.toStringAsFixed(1));
    }
  }

  math.Point<double>? _hotspotCanvasPoint(
    html.Element viewer,
    String name,
    num viewW,
    num viewH,
  ) {
    try {
      final data = js_util.callMethod(viewer, 'queryHotspot', [name]);
      if (data == null) return null;
      final canvas = js_util.getProperty(data, 'canvasPosition');
      if (canvas == null) return null;
      final x = _numProp(canvas, 'x');
      final y = _numProp(canvas, 'y');
      if (x == null || y == null) return null;
      if (!x.isFinite || !y.isFinite) return null;
      // Hide edges that project far off-canvas (behind camera, etc.).
      if (x < -80 || y < -80 || x > viewW + 80 || y > viewH + 80) {
        return null;
      }
      return math.Point(x, y);
    } catch (_) {
      return null;
    }
  }

  void _applyPartAppearance(html.Element el) {
    try {
      final model = js_util.getProperty(el, 'model');
      if (model == null) return;
      final materials = js_util.getProperty(model, 'materials');
      if (materials == null) return;
      final len = js_util.getProperty(materials, 'length');
      if (len is! int) return;
      final color = _selectedColor.color;
      final alpha = _xray ? 0.38 : 1.0;
      final rgba = <double>[color.r, color.g, color.b, alpha];
      for (var i = 0; i < len; i++) {
        final mat = js_util.getProperty(materials, i);
        if (mat == null) continue;
        try {
          js_util.callMethod(
            mat,
            'setAlphaMode',
            [_xray ? 'BLEND' : 'OPAQUE'],
          );
        } catch (_) {}
        try {
          js_util.setProperty(mat, 'doubleSided', _xray);
        } catch (_) {}
        final pbr = js_util.getProperty(mat, 'pbrMetallicRoughness');
        if (pbr == null) continue;
        js_util.callMethod(pbr, 'setBaseColorFactor', [rgba]);
        try {
          js_util.callMethod(pbr, 'setMetallicFactor', [0.15]);
          js_util.callMethod(pbr, 'setRoughnessFactor', [0.45]);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _selectColor(CadPartColor c) {
    setState(() => _colorId = c.id);
    final viewer = _viewer;
    if (viewer != null) {
      _applyPartAppearance(viewer);
    }
  }

  void _toggleXray() {
    setState(() => _xray = !_xray);
    final viewer = _viewer;
    if (viewer != null) {
      _applyPartAppearance(viewer);
    }
  }

  void _toggleStockOutline() {
    setState(() => _showStockOutline = !_showStockOutline);
    _syncStockOutline();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _studioBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          HtmlElementView(viewType: _viewType),
          if (_loading)
            ColoredBox(
              color: _studioBg.withValues(alpha: 0.85),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 8),
                    Text('Loading 3D…', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          if (_loadError != null)
            ColoredBox(
              color: _studioBg,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loading ? null : _reloadMesh,
                        child: const Text('Retry 3D'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_loadError == null)
            Positioned(
              left: 8,
              bottom: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < kCadPartColors.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _ColorSwatch(
                      color: kCadPartColors[i].color,
                      selected: kCadPartColors[i].id == _colorId,
                      tooltip: kCadPartColors[i].label,
                      onTap: () => _selectColor(kCadPartColors[i]),
                    ),
                  ],
                ],
              ),
            ),
          if (_loadError == null)
            Positioned(
              right: 4,
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ViewerToggle(
                    tooltip: _xray ? 'Solid part' : 'X-ray part',
                    icon: Icons.opacity,
                    selected: _xray,
                    onTap: _toggleXray,
                  ),
                  _ViewerToggle(
                    tooltip: _showStockOutline
                        ? 'Hide stock outline'
                        : 'Show stock outline',
                    icon: Icons.crop_square_outlined,
                    selected: _showStockOutline,
                    accent: const Color(0xFFF9A825),
                    onTap: _toggleStockOutline,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewerToggle extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool selected;
  final Color? accent;
  final VoidCallback onTap;

  const _ViewerToggle({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? (accent ?? Colors.white)
        : Colors.white70;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: selected ? 0.62 : 0.42),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.black87 : Colors.black26,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
