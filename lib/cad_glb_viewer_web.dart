// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

var _cadViewerCounter = 0;

/// Web 3D CAD preview via `<model-viewer>`.
///
/// Fetches the GLB through Dart/http first (long timeout + real error text),
/// then feeds a blob: URL to model-viewer so the CDN element is not the
/// thing timing out on a slow Toolpath tessellation.
class CadGlbViewer extends StatefulWidget {
  final String meshUrl;
  final double height;

  const CadGlbViewer({
    super.key,
    required this.meshUrl,
    this.height = 260,
  });

  @override
  State<CadGlbViewer> createState() => _CadGlbViewerState();
}

class _CadGlbViewerState extends State<CadGlbViewer> {
  late final String _viewType;
  html.DivElement? _host;
  String? _blobUrl;
  String? _loadError;
  bool _loading = true;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'cad-glb-viewer-${_cadViewerCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final host = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'relative';
      _host = host;
      return host;
    });
    // Defer until the platform view host exists.
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
    }
  }

  void _revokeBlob() {
    final url = _blobUrl;
    _blobUrl = null;
    if (url != null) {
      html.Url.revokeObjectUrl(url);
    }
  }

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
          bytes[0] != 0x67 || // g
          bytes[1] != 0x6c || // l
          bytes[2] != 0x54 || // T
          bytes[3] != 0x46) {
        // F
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
        final detail = decoded['detail'] ?? decoded['error'] ?? decoded['message'];
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
        await custom.whenDefined('model-viewer').timeout(
              const Duration(seconds: 20),
            );
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

    // Wait briefly for the platform view host if factory hasn't run yet.
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
      ..setAttribute('shadow-intensity', '0.6')
      ..setAttribute('exposure', '1')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.backgroundColor = '#2a2a2a';

    final completer = Completer<void>();
    el.on['load'].listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    el.on['error'].listen((_) {
      if (!completer.isCompleted) {
        completer.completeError('model-viewer failed to render GLB');
      }
    });

    host.children.clear();
    host.append(el);

    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      // Still show the viewer; some builds never fire load.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          HtmlElementView(viewType: _viewType),
          if (_loading)
            ColoredBox(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
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
              color: scheme.surfaceContainerHighest,
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
        ],
      ),
    );
  }
}
