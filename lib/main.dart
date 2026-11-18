import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'core/database/database_helper.dart';
import 'core/database/settings_repository.dart';
import 'features/camera/data/flutter_camera_source.dart';
import 'features/detection/data/performance_monitor.dart';
import 'features/detection/data/tflite_inference_engine.dart';
import 'features/gate/domain/gate_analyzer.dart';
import 'features/models/data/sqlite_model_repository.dart';
import 'features/safety/domain/safety_policy.dart';
import 'features/statistics/data/sqlite_session_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbHelper = DatabaseHelper();
  final settingsRepository = SettingsRepository(dbHelper);
  final inferenceEngine = TfliteInferenceEngine();
  final cameraSource = FlutterCameraSource();
  final safetyPolicy = const MaskSafetyPolicy();
  final gateAnalyzer = GateModeProcessor(safetyPolicy: safetyPolicy);
  final performanceMonitor = PerformanceMonitor();
  final sessionRepository = SqliteSessionRepository(dbHelper);

  final modelRepository = SqliteModelRepository(
    dbHelper: dbHelper,
    settingsRepository: settingsRepository,
    inferenceEngine: inferenceEngine,
    modelsStorageDirProvider: () async {
      final appDocs = await getApplicationDocumentsDirectory();
      return Directory(p.join(appDocs.path, 'models'));
    },
  );

  final controller = AppController(
    cameraSource: cameraSource,
    inferenceEngine: inferenceEngine,
    modelRepository: modelRepository,
    settingsRepository: settingsRepository,
    sessionRepository: sessionRepository,
    safetyPolicy: safetyPolicy,
    gateAnalyzer: gateAnalyzer,
    performanceMonitor: performanceMonitor,
  );

  await controller.initialize();
  runApp(SafeZoneApp(controller: controller));
}
