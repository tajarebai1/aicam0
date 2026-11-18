import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/detection_result.dart';
import '../domain/inference_engine.dart';

/// Concrete LiteRT / TFLite YOLO Detection inference engine.
/// Supports NHWC float32 and uint8 models, GPU delegate with automatic CPU fallback,
/// and standard Ultralytics YOLO detection output decoding + NMS.
class TfliteInferenceEngine implements InferenceEngine {
  Interpreter? _interpreter;
  String? _loadedModelPath;
  List<String> _labels = const [];
  AcceleratorType _activeAccelerator = AcceleratorType.cpu;

  int _inputHeight = 640;
  int _inputWidth = 640;
  TensorType _inputType = TensorType.float32;
  List<int> _outputShape = const [];

  @override
  bool get isLoaded => _interpreter != null;

  @override
  String? get loadedModelPath => _loadedModelPath;

  @override
  AcceleratorType get activeAccelerator => _activeAccelerator;

  Interpreter _createInterpreter(
    File file,
    AcceleratorType preferred,
    void Function(AcceleratorType actual) onActualAccelerator,
  ) {
    if (preferred == AcceleratorType.gpu && Platform.isAndroid) {
      try {
        final gpuOptions = InterpreterOptions()
          ..threads = 4
          ..addDelegate(GpuDelegateV2());
        final interp = Interpreter.fromFile(file, options: gpuOptions);
        onActualAccelerator(AcceleratorType.gpu);
        return interp;
      } catch (_) {
        // Automatic fallback to CPU if GPU delegate fails on this device
      }
    }

    final cpuOptions = InterpreterOptions()..threads = 4;
    final interp = Interpreter.fromFile(file, options: cpuOptions);
    onActualAccelerator(AcceleratorType.cpu);
    return interp;
  }

  @override
  Future<ModelInspectionResult> inspectAndSmokeTest(
    String modelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      return const ModelInspectionResult(
        isCompatible: false,
        inputWidth: 0,
        inputHeight: 0,
        inputLayout: 'unknown',
        tensorDtype: 'unknown',
        outputShape: [],
        smokeInferenceMs: 0,
        runtimeName: 'tflite_flutter',
        errorMessage: 'ملف النموذج غير موجود في التخزين الخاص.',
      );
    }

    Interpreter? tempInterpreter;
    try {
      var actualAcc = AcceleratorType.cpu;
      tempInterpreter = _createInterpreter(
        file,
        preferredAccelerator,
        (a) => actualAcc = a,
      );

      final inputTensor = tempInterpreter.getInputTensor(0);
      final outputTensor = tempInterpreter.getOutputTensor(0);
      final inShape = inputTensor.shape;
      final outShape = outputTensor.shape;

      if (inShape.length != 4 || inShape[0] != 1) {
        return ModelInspectionResult(
          isCompatible: false,
          inputWidth: 0,
          inputHeight: 0,
          inputLayout: inShape.toString(),
          tensorDtype: inputTensor.type.name,
          outputShape: outShape,
          smokeInferenceMs: 0,
          runtimeName: 'tflite_flutter(${actualAcc.name})',
          errorMessage: 'شكل الإدخال غير مدعوم ($inShape). المتوقع [1, H, W, 3] أو [1, 3, H, W].',
        );
      }

      final bool isNhwc = inShape[3] == 3;
      final bool isNchw = inShape[1] == 3;
      if (!isNhwc && !isNchw) {
        return ModelInspectionResult(
          isCompatible: false,
          inputWidth: 0,
          inputHeight: 0,
          inputLayout: inShape.toString(),
          tensorDtype: inputTensor.type.name,
          outputShape: outShape,
          smokeInferenceMs: 0,
          runtimeName: 'tflite_flutter(${actualAcc.name})',
          errorMessage: 'عدد القنوات اللونية غير متوافق مع RGB ($inShape).',
        );
      }

      final int height = isNhwc ? inShape[1] : inShape[2];
      final int width = isNhwc ? inShape[2] : inShape[3];
      final String layout = isNhwc ? 'NHWC' : 'NCHW';

      if (outShape.length != 3 || outShape[0] != 1) {
        return ModelInspectionResult(
          isCompatible: false,
          inputWidth: width,
          inputHeight: height,
          inputLayout: layout,
          tensorDtype: inputTensor.type.name,
          outputShape: outShape,
          smokeInferenceMs: 0,
          runtimeName: 'tflite_flutter(${actualAcc.name})',
          errorMessage: 'شكل الإخراج غير متوافق مع YOLO Detection ($outShape).',
        );
      }

      // Smoke inference using zero-filled tensor
      final sw = Stopwatch()..start();
      final dummyInput = _allocateDummyInput(inShape, inputTensor.type);
      final dummyOutput = _allocateOutputBuffer(outShape);
      tempInterpreter.run(dummyInput, dummyOutput);
      sw.stop();

      return ModelInspectionResult(
        isCompatible: true,
        inputWidth: width,
        inputHeight: height,
        inputLayout: layout,
        tensorDtype: inputTensor.type.name,
        outputShape: outShape,
        smokeInferenceMs: sw.elapsedMicroseconds / 1000.0,
        runtimeName: 'tflite_flutter(${actualAcc.name})',
      );
    } catch (e) {
      return ModelInspectionResult(
        isCompatible: false,
        inputWidth: 0,
        inputHeight: 0,
        inputLayout: 'unknown',
        tensorDtype: 'unknown',
        outputShape: const [],
        smokeInferenceMs: 0,
        runtimeName: 'tflite_flutter',
        errorMessage: 'فشل تحميل أو اختبار النموذج على الجهاز: $e',
      );
    } finally {
      tempInterpreter?.close();
    }
  }

  @override
  Future<void> load(
    String modelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    await dispose();
    final file = File(modelPath);
    if (!await file.exists()) {
      throw StateError('Model file does not exist: $modelPath');
    }

    var actualAcc = AcceleratorType.cpu;
    final interp = _createInterpreter(
      file,
      preferredAccelerator,
      (a) => actualAcc = a,
    );

    final inTensor = interp.getInputTensor(0);
    final outTensor = interp.getOutputTensor(0);
    final inShape = inTensor.shape;
    final bool isNhwc = inShape.length == 4 && inShape[3] == 3;

    _interpreter = interp;
    _loadedModelPath = modelPath;
    _labels = List<String>.from(labels);
    _activeAccelerator = actualAcc;
    _inputHeight = isNhwc ? inShape[1] : inShape[2];
    _inputWidth = isNhwc ? inShape[2] : inShape[3];
    _inputType = inTensor.type;
    _outputShape = List<int>.from(outTensor.shape);
  }

  @override
  Future<double> warmup() async {
    final interp = _interpreter;
    if (interp == null) return 0.0;
    final inTensor = interp.getInputTensor(0);
    final dummyInput = _allocateDummyInput(inTensor.shape, inTensor.type);
    final dummyOutput = _allocateOutputBuffer(_outputShape);

    final sw = Stopwatch()..start();
    interp.run(dummyInput, dummyOutput);
    sw.stop();
    return sw.elapsedMicroseconds / 1000.0;
  }

  @override
  Future<void> switchModel(
    String newModelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    await load(
      newModelPath,
      labels: labels,
      preferredAccelerator: preferredAccelerator,
    );
    await warmup();
  }

  @override
  Future<FrameDetectionResult> inferCameraImage(
    CameraImage image, {
    required int sensorOrientation,
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    final interp = _interpreter;
    if (interp == null) {
      return FrameDetectionResult(
        timestampUtc: DateTime.now().toUtc(),
        inferenceMs: 0,
        detections: const [],
        accelerator: _activeAccelerator,
      );
    }

    final sw = Stopwatch()..start();
    final inputBuffer = _preprocessCameraImage(
      image,
      targetWidth: _inputWidth,
      targetHeight: _inputHeight,
      sensorOrientation: sensorOrientation,
      isUint8: _inputType == TensorType.uint8,
    );
    final outputBuffer = _allocateOutputBuffer(_outputShape);

    interp.run(inputBuffer, outputBuffer);
    final detections = decodeYoloOutput(
      output: outputBuffer[0],
      outputShape: _outputShape,
      labels: _labels,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
      inputWidth: _inputWidth,
      inputHeight: _inputHeight,
    );
    sw.stop();

    return FrameDetectionResult(
      timestampUtc: DateTime.now().toUtc(),
      inferenceMs: sw.elapsedMicroseconds / 1000.0,
      detections: detections,
      accelerator: _activeAccelerator,
    );
  }

  /// Decodes Ultralytics YOLO detection output tensor `[1, 4+C, N]` or `[1, N, 4+C]`
  /// (or pre-NMS `[1, N, 6]`) into normalized `DetectionItem`s with NMS.
  static List<DetectionItem> decodeYoloOutput({
    required List<List<double>> output,
    required List<int> outputShape,
    required List<String> labels,
    required double confidenceThreshold,
    required double iouThreshold,
    required int inputWidth,
    required int inputHeight,
  }) {
    if (outputShape.length != 3) return const [];
    final dim1 = outputShape[1];
    final dim2 = outputShape[2];
    final numClasses = labels.isEmpty ? 3 : labels.length;

    final rawDetections = <DetectionItem>[];

    // Case A: Pre-NMS output [1, N, 6] -> [x1, y1, x2, y2, score, classId]
    if (dim2 == 6 && dim1 > 6) {
      for (int i = 0; i < dim1; i++) {
        final row = output[i];
        final score = row[4];
        if (score < confidenceThreshold) continue;
        final clsIdx = row[5].round();
        final label = (clsIdx >= 0 && clsIdx < labels.length)
            ? labels[clsIdx]
            : 'class_$clsIdx';
        final bool normalized = row[2] <= 1.5 && row[3] <= 1.5;
        final box = BoundingBox(
          left: (normalized ? row[0] : row[0] / inputWidth).clamp(0.0, 1.0),
          top: (normalized ? row[1] : row[1] / inputHeight).clamp(0.0, 1.0),
          right: (normalized ? row[2] : row[2] / inputWidth).clamp(0.0, 1.0),
          bottom: (normalized ? row[3] : row[3] / inputHeight).clamp(0.0, 1.0),
        );
        rawDetections.add(
          DetectionItem(
            classIndex: clsIdx,
            label: label,
            confidence: score.clamp(0.0, 1.0),
            box: box,
          ),
        );
      }
      return rawDetections;
    }

    // Case B: Ultralytics standard [1, 4+C, N] (channels-first)
    final bool channelsFirst = dim1 < dim2;
    final int numAnchors = channelsFirst ? dim2 : dim1;
    final int stride = channelsFirst ? dim1 : dim2;
    if (stride < 5) return const [];

    for (int i = 0; i < numAnchors; i++) {
      final cx = channelsFirst ? output[0][i] : output[i][0];
      final cy = channelsFirst ? output[1][i] : output[i][1];
      final w = channelsFirst ? output[2][i] : output[i][2];
      final h = channelsFirst ? output[3][i] : output[i][3];

      int bestClass = -1;
      double bestScore = 0.0;
      final classCount = math.min(numClasses, stride - 4);
      for (int c = 0; c < classCount; c++) {
        final score = channelsFirst ? output[4 + c][i] : output[i][4 + c];
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }

      if (bestClass < 0 || bestScore < confidenceThreshold) continue;

      final bool isNormalized = w <= 1.5 && h <= 1.5 && cx <= 1.5 && cy <= 1.5;
      final normCx = isNormalized ? cx : cx / inputWidth;
      final normCy = isNormalized ? cy : cy / inputHeight;
      final normW = isNormalized ? w : w / inputWidth;
      final normH = isNormalized ? h : h / inputHeight;

      final left = (normCx - normW / 2.0).clamp(0.0, 1.0);
      final top = (normCy - normH / 2.0).clamp(0.0, 1.0);
      final right = (normCx + normW / 2.0).clamp(0.0, 1.0);
      final bottom = (normCy + normH / 2.0).clamp(0.0, 1.0);

      final label = (bestClass < labels.length) ? labels[bestClass] : 'class_$bestClass';
      rawDetections.add(
        DetectionItem(
          classIndex: bestClass,
          label: label,
          confidence: bestScore.clamp(0.0, 1.0),
          box: BoundingBox(left: left, top: top, right: right, bottom: bottom),
        ),
      );
    }

    return _applyNms(rawDetections, iouThreshold);
  }

  static List<DetectionItem> _applyNms(
    List<DetectionItem> detections,
    double iouThreshold,
  ) {
    if (detections.length <= 1) return detections;
    final sorted = List<DetectionItem>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <DetectionItem>[];

    while (sorted.isNotEmpty) {
      final current = sorted.removeAt(0);
      kept.add(current);
      sorted.removeWhere(
        (other) => current.box.iou(other.box) > iouThreshold,
      );
    }
    return kept;
  }

  Object _allocateDummyInput(List<int> shape, TensorType type) {
    final total = shape.reduce((a, b) => a * b);
    if (type == TensorType.uint8) {
      return Uint8List(total).reshape(shape);
    }
    return Float32List(total).reshape(shape);
  }

  List<List<List<double>>> _allocateOutputBuffer(List<int> shape) {
    return List.generate(
      shape[0],
      (_) => List.generate(
        shape[1],
        (_) => List<double>.filled(shape[2], 0.0),
      ),
    );
  }

  /// Fast zero-retention YUV420 / BGRA8888 preprocessing into NHWC tensor buffer.
  Object _preprocessCameraImage(
    CameraImage image, {
    required int targetWidth,
    required int targetHeight,
    required int sensorOrientation,
    required bool isUint8,
  }) {
    final int srcW = image.width;
    final int srcH = image.height;
    final int total = targetWidth * targetHeight * 3;
    final Float32List? floatBuf = isUint8 ? null : Float32List(total);
    final Uint8List? uint8Buf = isUint8 ? Uint8List(total) : null;

    final bool isYuv = image.planes.length >= 3;
    final yPlane = image.planes[0];
    final uPlane = isYuv ? image.planes[1] : null;
    final vPlane = isYuv ? image.planes[2] : null;

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane?.bytesPerRow ?? 0;
    final int uvPixelStride = uPlane?.bytesPerPixel ?? 1;

    int outIdx = 0;
    for (int ty = 0; ty < targetHeight; ty++) {
      for (int tx = 0; tx < targetWidth; tx++) {
        // Map target (tx, ty) to source coordinates respecting sensor rotation
        final double nx = tx / targetWidth;
        final double ny = ty / targetHeight;
        int sx;
        int sy;
        if (sensorOrientation == 90) {
          sx = (ny * (srcW - 1)).round();
          sy = ((1.0 - nx) * (srcH - 1)).round();
        } else if (sensorOrientation == 270) {
          sx = ((1.0 - ny) * (srcW - 1)).round();
          sy = (nx * (srcH - 1)).round();
        } else if (sensorOrientation == 180) {
          sx = ((1.0 - nx) * (srcW - 1)).round();
          sy = ((1.0 - ny) * (srcH - 1)).round();
        } else {
          sx = (nx * (srcW - 1)).round();
          sy = (ny * (srcH - 1)).round();
        }

        int r = 0, g = 0, b = 0;
        if (isYuv && uPlane != null && vPlane != null) {
          final int yIndex = sy * yRowStride + sx;
          final int uvIndex = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
          final int yp = yPlane.bytes[yIndex];
          final int up = uPlane.bytes[uvIndex];
          final int vp = vPlane.bytes[uvIndex];

          r = (yp + 1.402 * (vp - 128)).round().clamp(0, 255);
          g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round().clamp(0, 255);
          b = (yp + 1.772 * (up - 128)).round().clamp(0, 255);
        } else {
          final int idx = sy * yRowStride + sx * 4;
          b = yPlane.bytes[idx];
          g = yPlane.bytes[idx + 1];
          r = yPlane.bytes[idx + 2];
        }

        if (isUint8) {
          uint8Buf![outIdx++] = r;
          uint8Buf[outIdx++] = g;
          uint8Buf[outIdx++] = b;
        } else {
          floatBuf![outIdx++] = r / 255.0;
          floatBuf[outIdx++] = g / 255.0;
          floatBuf[outIdx++] = b / 255.0;
        }
      }
    }

    if (isUint8) {
      return uint8Buf!.reshape([1, targetHeight, targetWidth, 3]);
    }
    return floatBuf!.reshape([1, targetHeight, targetWidth, 3]);
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _loadedModelPath = null;
  }
}
