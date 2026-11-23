// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'quote_cad_analysis.dart';

var _cadViewerCounter = 0;

/// Preset part tints for the Toolpath GLB (baseColorFactor).
class CadPartColor {
  final String id;
  final String label;
  final Color color;

  const CadPartColor(this.id, this.label, this.color);
}

const kCadPartColors = <CadPartColor>[
  CadPartColor('aluminum', 'Aluminum', Color(0xFF8B96A3)),
  CadPartColor('blue', 'Shop blue', Color(0xFF3D6FA8)),
  CadPartColor('charcoal', 'Charcoal', Color(0xFF3A3A3A)),
];

/// Web 3D CAD preview via `<model-viewer>`.
///
/// When [fixtureDown] is set, the model is rotated so that direction points
/// toward world −Y (table down), then the camera resets to a three-quarter
/// view from above.
class CadGlbViewer extends StatefulWidget {
  final String meshUrl;

  /// Unit vector in model space pointing toward the fixture (table).
  final CadVec3? fixtureDown;

  const CadGlbViewer({
    super.key,
    required this.meshUrl,
    this.fixtureDown,
  });

  @override
  State<CadGlbViewer> createState() => _CadGlbViewerState();
}

class _CadGlbViewerState extends State<CadGlbViewer> {
  static const _studioBg = Color(0xFFF4F4F4);
  static const _worldDown = CadVec3(0, -1, 0);

  late final String _viewType;
  html.DivElement? _host;
  html.Element? _viewer;
  String? _blobUrl;
  String? _loadError;
  bool _loading = true;
  int _loadGen = 0;
  String _colorId = kCadPartColors.first.id;

  @override
  void initState() {
    super.initState();
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
    final oldDown = oldWidget.fixtureDown;
    final newDown = widget.fixtureDown;
    final changed = (oldDown == null) != (newDown == null) ||
        (oldDown != null &&
            newDown != null &&
            !oldDown.nearlyEquals(newDown));
    if (changed) {
      _applyFixtureOrientation(_viewer);
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

    final el = html.Element.tag('model-viewer')
      ..setAttribute('src', blobUrl)
      ..setAttribute('camera-controls', '')
      ..setAttribute('touch-action', 'pan-y')
      ..setAttribute('interaction-prompt', 'none')
      ..setAttribute('shadow-intensity', '0.85')
      ..setAttribute('exposure', '1.1')
      ..setAttribute('environment-image', 'neutral')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.backgroundColor = '#f4f4f4';

    final completer = Completer<void>();
    el.on['load'].listen((_) {
      _applyPartColor(el, _selectedColor.color);
      _applyFixtureOrientation(el);
      if (!completer.isCompleted) completer.complete();
    });
    el.on['error'].listen((_) {
      if (!completer.isCompleted) {
        completer.completeError('model-viewer failed to render GLB');
      }
    });

    host.children.clear();
    host.append(el);
    _viewer = el;
    _applyFixtureOrientation(el);

    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _applyPartColor(el, _selectedColor.color);
      _applyFixtureOrientation(el);
    }
  }

  /// Rotate model so [fixtureDown] maps to world −Y, then reset orbit.
  void _applyFixtureOrientation(html.Element? el) {
    if (el == null) return;
    final down = widget.fixtureDown;
    final orient = down == null
        ? '0deg 0deg 0deg'
        : _orientationAttrAligning(down.normalized(), _worldDown);
    el.setAttribute('orientation', orient);
    // Three-quarter from above after reorient (phi from +Y).
    el.setAttribute('camera-orbit', '35deg 65deg 105%');
    el.setAttribute('camera-target', 'auto auto auto');
    try {
      js_util.callMethod(el, 'jumpCameraToGoal', []);
    } catch (_) {
      // Older model-viewer — attribute change still interpolates.
    }
  }

  /// Euler XYZ string for model-viewer that maps [from] → [to].
  String _orientationAttrAligning(CadVec3 from, CadVec3 to) {
    final euler = _rotationEulerXyzAligning(from, to);
    String deg(double rad) => '${(rad * 180 / math.pi).toStringAsFixed(2)}deg';
    return '${deg(euler[0])} ${deg(euler[1])} ${deg(euler[2])}';
  }

  /// Roll/pitch/yaw (radians) for intrinsic XYZ rotation mapping [from]→[to].
  List<double> _rotationEulerXyzAligning(CadVec3 from, CadVec3 to) {
    final a = from.normalized();
    final b = to.normalized();
    final c = a.dot(b).clamp(-1.0, 1.0);
    if (c > 0.999999) return const [0, 0, 0];
    late CadVec3 axis;
    late double angle;
    if (c < -0.999999) {
      axis = (a.x.abs() < 0.9
              ? const CadVec3(1, 0, 0)
              : const CadVec3(0, 1, 0))
          .cross(a)
          .normalized();
      angle = math.pi;
    } else {
      axis = a.cross(b).normalized();
      angle = math.acos(c);
    }
    return _axisAngleToEulerXyz(axis, angle);
  }

  List<double> _axisAngleToEulerXyz(CadVec3 axis, double angle) {
    final x = axis.x;
    final y = axis.y;
    final z = axis.z;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final t = 1 - cosA;
    final r00 = t * x * x + cosA;
    final r10 = t * x * y + sinA * z;
    final r11 = t * y * y + cosA;
    final r12 = t * y * z - sinA * x;
    final r20 = t * x * z - sinA * y;
    final r21 = t * y * z + sinA * x;
    final r22 = t * z * z + cosA;

    final pitch = math.asin((-r20).clamp(-1.0, 1.0));
    double roll;
    double yaw;
    if (r20.abs() < 0.999999) {
      roll = math.atan2(r21, r22);
      yaw = math.atan2(r10, r00);
    } else {
      roll = math.atan2(-r12, r11);
      yaw = 0;
    }
    return [roll, pitch, yaw];
  }

  void _applyPartColor(html.Element el, Color color) {
    try {
      final model = js_util.getProperty(el, 'model');
      if (model == null) return;
      final materials = js_util.getProperty(model, 'materials');
      if (materials == null) return;
      final len = js_util.getProperty(materials, 'length');
      if (len is! int) return;
      final rgba = <double>[
        color.r,
        color.g,
        color.b,
        1.0,
      ];
      for (var i = 0; i < len; i++) {
        final mat = js_util.getProperty(materials, i);
        if (mat == null) continue;
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
      _applyPartColor(viewer, c.color);
    }
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
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  for (final c in kCadPartColors) ...[
                    _ColorSwatch(
                      color: c.color,
                      selected: c.id == _colorId,
                      tooltip: c.label,
                      onTap: () => _selectColor(c),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const Spacer(),
                  if (widget.fixtureDown != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Down ${cadDirectionLabel(widget.fixtureDown!)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
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
