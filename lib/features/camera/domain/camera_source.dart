import 'package:camera/camera.dart';

enum CameraLensChoice {
  front,
  rear,
}

enum CameraPermissionState {
  unknown,
  granted,
  denied,
  permanentlyDenied,
  unavailable,
}

/// Abstract single-owner camera interface (ADR-001).
/// Never run Flutter `camera` and another native camera session simultaneously.
abstract class CameraSource {
  CameraController? get controller;
  CameraLensChoice get currentLens;
  bool get isRunning;
  CameraPermissionState get permissionState;
  String? get lastError;

  Future<CameraPermissionState> ensurePermission();
  Future<void> start({CameraLensChoice? lens});
  Future<void> stop();
  Future<void> switchLens();
  void observeFrame(void Function(CameraImage image, int sensorOrientation, bool isFront) onFrame);
  Future<void> dispose();
}
