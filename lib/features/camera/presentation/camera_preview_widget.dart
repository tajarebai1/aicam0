import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../detection/domain/detection_result.dart';
import '../../gate/domain/gate_episode.dart';

/// Displays the live camera preview with aspect-ratio protection for
/// standard and foldable screens (e.g., Galaxy Z Flip3) plus detection overlay.
class CameraPreviewWithOverlay extends StatelessWidget {
  const CameraPreviewWithOverlay({
    super.key,
    required this.controller,
    required this.detections,
    required this.isFrontCamera,
    this.showGateRoi = false,
    this.gateRoi = GateRoi.defaultDoorRoi,
  });

  final CameraController controller;
  final List<DetectionItem> detections;
  final bool isFrontCamera;
  final bool showGateRoi;
  final GateRoi gateRoi;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final previewSize = controller.value.previewSize;
    final orientation = MediaQuery.of(context).orientation;

    double aspectRatio = controller.value.aspectRatio;
    if (previewSize != null && previewSize.height > 0) {
      aspectRatio = orientation == Orientation.portrait
          ? previewSize.height / previewSize.width
          : previewSize.width / previewSize.height;
    }

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              CustomPaint(
                painter: DetectionOverlayPainter(
                  detections: detections,
                  isFrontCamera: isFrontCamera,
                  showGateRoi: showGateRoi,
                  gateRoi: gateRoi,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetectionOverlayPainter extends CustomPainter {
  DetectionOverlayPainter({
    required this.detections,
    required this.isFrontCamera,
    required this.showGateRoi,
    required this.gateRoi,
  });

  final List<DetectionItem> detections;
  final bool isFrontCamera;
  final bool showGateRoi;
  final GateRoi gateRoi;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGateRoi) {
      final roiRect = Rect.fromLTRB(
        gateRoi.left * size.width,
        gateRoi.top * size.height,
        gateRoi.right * size.width,
        gateRoi.bottom * size.height,
      );
      final roiPaint = Paint()
        ..color = Colors.amberAccent.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(roiRect, roiPaint);
    }

    for (final det in detections) {
      final box = det.box;
      final leftNorm = isFrontCamera ? (1.0 - box.right) : box.left;
      final rightNorm = isFrontCamera ? (1.0 - box.left) : box.right;

      final rect = Rect.fromLTRB(
        (leftNorm.clamp(0.0, 1.0)) * size.width,
        (box.top.clamp(0.0, 1.0)) * size.height,
        (rightNorm.clamp(0.0, 1.0)) * size.width,
        (box.bottom.clamp(0.0, 1.0)) * size.height,
      );

      final color = _colorForLabel(det.label);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );

      final labelText = '${det.label} ${(det.confidence * 100).toStringAsFixed(0)}%';
      final textSpan = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final bgRect = Rect.fromLTWH(
        rect.left,
        (rect.top - textPainter.height - 6).clamp(0.0, size.height - 20),
        textPainter.width + 10,
        textPainter.height + 4,
      );
      canvas.drawRect(bgRect, Paint()..color = color.withOpacity(0.85));
      textPainter.paint(canvas, Offset(bgRect.left + 5, bgRect.top + 2));
    }
  }

  Color _colorForLabel(String label) {
    final lower = label.toLowerCase();
    if (lower == 'with_mask' || lower == 'compliant') {
      return const Color(0xFF16A34A);
    }
    if (lower == 'without_mask' ||
        lower == 'mask_weared_incorrect' ||
        lower == 'violation') {
      return const Color(0xFFDC2626);
    }
    return const Color(0xFFD97706);
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.isFrontCamera != isFrontCamera ||
        oldDelegate.showGateRoi != showGateRoi;
  }
}
