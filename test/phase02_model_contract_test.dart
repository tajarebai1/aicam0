import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safezone_mobile/core/database/database_helper.dart';
import 'package:safezone_mobile/core/database/settings_repository.dart';
import 'package:safezone_mobile/features/detection/domain/detection_result.dart';
import 'package:safezone_mobile/features/detection/domain/inference_engine.dart';
import 'package:safezone_mobile/features/models/data/sqlite_model_repository.dart';

class _FakeInferenceEngine implements InferenceEngine {
  bool failNextSwitch = false;
  bool failNextInspect = false;
  String? _loadedPath;

  @override
  bool get isLoaded => _loadedPath != null;

  @override
  String? get loadedModelPath => _loadedPath;

  @override
  AcceleratorType get activeAccelerator => AcceleratorType.cpu;

  @override
  Future<ModelInspectionResult> inspectAndSmokeTest(
    String modelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    if (failNextInspect) {
      failNextInspect = false;
      return const ModelInspectionResult(
        isCompatible: false,
        inputWidth: 0,
        inputHeight: 0,
        inputLayout: 'unknown',
        tensorDtype: 'unknown',
        outputShape: [],
        smokeInferenceMs: 0,
        runtimeName: 'fake',
        errorMessage: 'ملف نموذج معطوب أو غير متوافق',
      );
    }
    return const ModelInspectionResult(
      isCompatible: true,
      inputWidth: 640,
      inputHeight: 640,
      inputLayout: 'NHWC',
      tensorDtype: 'float32',
      outputShape: [1, 7, 8400],
      smokeInferenceMs: 12.5,
      runtimeName: 'fake_cpu',
    );
  }

  @override
  Future<void> load(
    String modelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    _loadedPath = modelPath;
  }

  @override
  Future<void> switchModel(
    String newModelPath, {
    required List<String> labels,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    if (failNextSwitch) {
      failNextSwitch = false;
      throw StateError('Simulated runtime crash during model switch');
    }
    _loadedPath = newModelPath;
  }

  @override
  Future<double> warmup() async => 8.0;

  @override
  Future<FrameDetectionResult> inferCameraImage(
    CameraImage image, {
    required int sensorOrientation,
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {
    _loadedPath = null;
  }
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late SettingsRepository settingsRepo;
  late _FakeInferenceEngine fakeEngine;
  late SqliteModelRepository modelRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('safezone_p02_test_');
    dbHelper = DatabaseHelper(
      customPath: p.join(tempDir.path, 'test.db'),
      factoryOverride: databaseFactoryFfi,
    );
    settingsRepo = SettingsRepository(dbHelper);
    fakeEngine = _FakeInferenceEngine();
    modelRepo = SqliteModelRepository(
      dbHelper: dbHelper,
      settingsRepository: settingsRepo,
      inferenceEngine: fakeEngine,
      modelsStorageDirProvider: () async => Directory(p.join(tempDir.path, 'private_models')),
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P02 — Dynamic Model Contract (T05, T06, T07, T08, T09)', () {
    test('imports valid .tflite, rejects duplicate SHA-256, and persists active model', () async {
      final fA = File(p.join(tempDir.path, 'mask_v4.tflite'));
      await fA.writeAsBytes(List<int>.generate(64, (i) => i));

      final import1 = await modelRepo.importModel(sourceFilePath: fA.path);
      expect(import1.success, isTrue);
      expect(import1.model, isNotNull);

      // Duplicate import rejected
      final importDup = await modelRepo.importModel(sourceFilePath: fA.path);
      expect(importDup.success, isFalse);
      expect(importDup.isDuplicate, isTrue);

      // Activate A and verify persistence
      final actA = await modelRepo.setActive(import1.model!.id);
      expect(actA.success, isTrue);
      final persisted = await modelRepo.getActiveModel();
      expect(persisted?.id, import1.model!.id);
    });

    test('rejects corrupt/incompatible model safely (T06)', () async {
      final badFile = File(p.join(tempDir.path, 'corrupt.tflite'));
      await badFile.writeAsBytes([9, 9, 9]);
      fakeEngine.failNextInspect = true;

      final res = await modelRepo.importModel(sourceFilePath: badFile.path);
      expect(res.success, isFalse);
      expect((await modelRepo.listModels()), isEmpty);
    });

    test('rolls back to previous working model A when switching to B fails (T08)', () async {
      final fA = File(p.join(tempDir.path, 'model_a.tflite'));
      final fB = File(p.join(tempDir.path, 'model_b.tflite'));
      await fA.writeAsBytes([1, 2, 3, 4]);
      await fB.writeAsBytes([5, 6, 7, 8]);

      final resA = await modelRepo.importModel(sourceFilePath: fA.path);
      final resB = await modelRepo.importModel(sourceFilePath: fB.path);
      expect(resA.success, isTrue);
      expect(resB.success, isTrue);

      final actA = await modelRepo.setActive(resA.model!.id);
      expect(actA.success, isTrue);

      // Simulate runtime failure while activating B
      fakeEngine.failNextSwitch = true;
      final actB = await modelRepo.setActive(resB.model!.id);

      expect(actB.success, isFalse);
      expect(actB.rolledBack, isTrue);
      expect(actB.activeModel?.id, resA.model!.id);
      expect((await modelRepo.getActiveModel())?.id, resA.model!.id);
    });
  });
}
