import 'dart:math' as math;

enum AcceleratorType {
  cpu,
  gpu,
  other,
  unknown,
}

extension AcceleratorTypeX on AcceleratorType {
  String get dbValue => name;

  static AcceleratorType fromString(String value) {
    return AcceleratorType.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => AcceleratorType.cpu,
    );
  }
}

/// Normalized bounding box in [0.0, 1.0] coordinates.
class BoundingBox {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => math.max(0.0, right - left);
  double get height => math.max(0.0, bottom - top);
  double get area => width * height;
  double get centerX => (left + right) / 2.0;
  double get centerY => (top + bottom) / 2.0;

  double iou(BoundingBox other) {
    final interLeft = math.max(left, other.left);
    final interTop = math.max(top, other.top);
    final interRight = math.min(right, other.right);
    final interBottom = math.min(bottom, other.bottom);

    final interW = math.max(0.0, interRight - interLeft);
    final interH = math.max(0.0, interBottom - interTop);
    final interArea = interW * interH;
    final unionArea = area + other.area - interArea;
    if (unionArea <= 0) return 0.0;
    return interArea / unionArea;
  }
}

class DetectionItem {
  const DetectionItem({
    required this.classIndex,
    required this.label,
    required this.confidence,
    required this.box,
  });

  final int classIndex;
  final String label;
  final double confidence;
  final BoundingBox box;
}

class FrameDetectionResult {
  const FrameDetectionResult({
    required this.timestampUtc,
    required this.inferenceMs,
    required this.detections,
    required this.accelerator,
  });

  final DateTime timestampUtc;
  final double inferenceMs;
  final List<DetectionItem> detections;
  final AcceleratorType accelerator;
}

class ModelInspectionResult {
  const ModelInspectionResult({
    required this.isCompatible,
    required this.inputWidth,
    required this.inputHeight,
    required this.inputLayout,
    required this.tensorDtype,
    required this.outputShape,
    required this.smokeInferenceMs,
    required this.runtimeName,
    this.errorMessage,
  });

  final bool isCompatible;
  final int inputWidth;
  final int inputHeight;
  final String inputLayout;
  final String tensorDtype;
  final List<int> outputShape;
  final double smokeInferenceMs;
  final String runtimeName;
  final String? errorMessage;
}
