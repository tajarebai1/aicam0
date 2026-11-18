import 'dart:async';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/camera_source.dart';

/// Sole owner of the live Android camera session.
/// Implements latest-frame-only backpressure and never saves photos or video.
class FlutterCameraSource implements CameraSource {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraLensChoice _currentLens = CameraLensChoice.rear;
  CameraPermissionState _permissionState = CameraPermissionState.unknown;
  bool _isRunning = false;
  bool _isStreaming = false;
  bool _isBusy = false;
  String? _lastError;

  void Function(CameraImage image, int sensorOrientation, bool isFront)? _frameCallback;

  @override
  CameraController? get controller => _controller;

  @override
  CameraLensChoice get currentLens => _currentLens;

  @override
  bool get isRunning => _isRunning;

  @override
  CameraPermissionState get permissionState => _permissionState;

  @override
  String? get lastError => _lastError;

  @override
  Future<CameraPermissionState> ensurePermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      _permissionState = CameraPermissionState.granted;
      return _permissionState;
    }
    final requested = await Permission.camera.request();
    if (requested.isGranted) {
      _permissionState = CameraPermissionState.granted;
    } else if (requested.isPermanentlyDenied) {
      _permissionState = CameraPermissionState.permanentlyDenied;
      _lastError = 'تم رفض إذن الكاميرا بشكل دائم. يرجى تفعيله من إعدادات النظام.';
    } else {
      _permissionState = CameraPermissionState.denied;
      _lastError = 'مطلوب إذن الكاميرا لبدء المراقبة الحية.';
    }
    return _permissionState;
  }

  @override
  Future<void> start({CameraLensChoice? lens}) async {
    _lastError = null;
    if (lens != null) {
      _currentLens = lens;
    }

    final perm = await ensurePermission();
    if (perm != CameraPermissionState.granted) {
      return;
    }

    try {
      await stop();
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _permissionState = CameraPermissionState.unavailable;
        _lastError = 'لا توجد كاميرا متاحة على هذا الجهاز.';
        return;
      }

      final targetDirection = _currentLens == CameraLensChoice.front
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      final selected = _cameras.firstWhere(
        (c) => c.lensDirection == targetDirection,
        orElse: () => _cameras.first,
      );

      _currentLens = selected.lensDirection == CameraLensDirection.front
          ? CameraLensChoice.front
          : CameraLensChoice.rear;

      final ctrl = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false, // Privacy: never request microphone or audio
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await ctrl.initialize();
      _controller = ctrl;
      _isRunning = true;

      await _startStreamIfNeeded();
    } on CameraException catch (e) {
      _isRunning = false;
      _lastError = 'تعذر تشغيل الكاميرا (${e.code}): ${e.description ?? ''}';
    } catch (e) {
      _isRunning = false;
      _lastError = 'خطأ غير متوقع في الكاميرا: $e';
    }
  }

  Future<void> _startStreamIfNeeded() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isStreaming) return;
    if (_frameCallback == null) return;

    _isStreaming = true;
    final sensorOrientation = ctrl.description.sensorOrientation;
    final isFront = ctrl.description.lensDirection == CameraLensDirection.front;

    await ctrl.startImageStream((CameraImage image) {
      if (_isBusy) return;
      _isBusy = true;
      try {
        _frameCallback?.call(image, sensorOrientation, isFront);
      } finally {
        _isBusy = false;
      }
    });
  }

  @override
  void observeFrame(
    void Function(CameraImage image, int sensorOrientation, bool isFront) onFrame,
  ) {
    _frameCallback = onFrame;
    if (_isRunning && !_isStreaming) {
      unawaited(_startStreamIfNeeded());
    }
  }

  @override
  Future<void> switchLens() async {
    final nextLens = _currentLens == CameraLensChoice.rear
        ? CameraLensChoice.front
        : CameraLensChoice.rear;
    await start(lens: nextLens);
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    final ctrl = _controller;
    _controller = null;

    if (ctrl != null) {
      try {
        if (_isStreaming && ctrl.value.isStreamingImages) {
          await ctrl.stopImageStream();
        }
      } catch (_) {
        // Ignore stop stream errors during lifecycle transitions
      } finally {
        _isStreaming = false;
      }
      try {
        await ctrl.dispose();
      } catch (_) {
        // Ignore dispose errors on fold/lifecycle switches
      }
    }
  }

  @override
  Future<void> dispose() async {
    _frameCallback = null;
    await stop();
  }
}
