// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

var _cadViewerCounter = 0;

/// Web 3D CAD preview via `<model-viewer>` + a Toolpath GLB URL (MCP proxy).
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
  html.Element? _viewer;
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _viewType = 'cad-glb-viewer-${_cadViewerCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final host = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'relative';
      _ensureModelViewer(host);
      return host;
    });
  }

  Future<void> _ensureModelViewer(html.DivElement host) async {
    try {
      final custom = html.window.customElements;
      if (custom != null) {
        await custom.whenDefined('model-viewer');
      }
    } catch (_) {
      // Script may already have defined it, or CDN blocked.
    }
    if (!mounted) return;
    final el = html.Element.tag('model-viewer')
      ..setAttribute('camera-controls', '')
      ..setAttribute('touch-action', 'pan-y')
      ..setAttribute('interaction-prompt', 'none')
      ..setAttribute('shadow-intensity', '0.6')
      ..setAttribute('exposure', '1')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.backgroundColor = '#2a2a2a';
    el.setAttribute('src', widget.meshUrl);
    el.on['load'].listen((_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = null;
      });
    });
    el.on['error'].listen((_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load 3D mesh — try Re-analyze';
      });
    });
    host.children.clear();
    host.append(el);
    _viewer = el;
  }

  @override
  void didUpdateWidget(covariant CadGlbViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meshUrl != widget.meshUrl && _viewer != null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
      _viewer!.setAttribute('src', widget.meshUrl);
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
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_loadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
