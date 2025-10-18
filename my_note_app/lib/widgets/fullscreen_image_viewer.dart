import 'package:flutter/material.dart';

class FullscreenImageViewer extends StatefulWidget {
  final String url;
  final String heroTag;
  const FullscreenImageViewer({
    super.key,
    required this.url,
    required this.heroTag,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  // ค่าซูม
  static const double _minScale = 1.0;
  static const double _maxScale = 5.0;
  static const double _doubleTapZoom = 2.5;

  void _handleDoubleTap() {
    final matrix = _controller.value;
    final isZoomed = matrix.getMaxScaleOnAxis() > 1.02;

    if (!isZoomed) {
      // ซูมเข้าไปที่จุดแตะ
      final tapPos = _doubleTapDetails!.localPosition;
      final zoom = Matrix4.identity()
        ..translate(-tapPos.dx * (_doubleTapZoom - 1),
                    -tapPos.dy * (_doubleTapZoom - 1))
        ..scale(_doubleTapZoom);
      _controller.value = zoom;
    } else {
      // รีเซ็ตกลับ 1x
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: GestureDetector(
          onTapDown: (d) => _doubleTapDetails = d,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: _minScale,
            maxScale: _maxScale,
            panEnabled: true,
            scaleEnabled: true,
            boundaryMargin: const EdgeInsets.all(80),
            child: Hero(
              tag: widget.heroTag,
              child: Image.network(
                widget.url,
                fit: BoxFit.contain,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    width: 64,
                    height: 64,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
