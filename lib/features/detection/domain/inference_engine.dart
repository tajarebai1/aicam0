import 'package:camera/camera.dart';

import 'detection_result.dart';

/// Replaceable inference adapter contract (ADR-002).
/// Must never retain camera frames or save media.
abstract class InferenceEngine {
  bool get isLoaded;
  String? get loadedModelPath;
  AcceleratorType get activeAccelerator;

  /// Inspects tensors and executes a device smoke inference without replacing
  /// the currently active model.
  Future<ModelInspectionResult> inspectAndSmokeTest(
    String modelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  });

  /// Loads a validated model file into the active runtime.
  Future<void> load(
    String modelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  });

  /// Runs a warmup inference pass on a dummy tensor.
  Future<double> warmup();

  /// Runs detection inference on a live camera frame.
  Future<FrameDetectionResult> inferCameraImage(
    CameraImage image, {
    required int sensorOrientation,
    required double confidenceThreshold,
    required double iouThreshold,
  });

  /// Switches active model atomically.
  Future<void> switchModel(
    String newModelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  });

  Future<void> dispose();
}
