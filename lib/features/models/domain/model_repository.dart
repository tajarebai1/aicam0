import '../../detection/domain/detection_result.dart';
import 'model_entry.dart';

abstract class ModelRepository {
  Future<ModelImportResult> importModel({
    required String sourceFilePath,
    String? displayNameOverride,
    String? manifestJsonPath,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  });

  Future<List<ModelEntry>> listModels();

  Future<ModelEntry?> getModelById(String id);

  Future<ModelEntry?> getActiveModel();

  Future<ModelProfile> getProfileForModel(String modelId);

  Future<void> saveProfile(ModelProfile profile);

  Future<ModelInspectionResult> validate(
    String modelId, {
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  });

  /// Activates [modelId] after on-device validation/load; rolls back to the
  /// previous working model automatically if activation fails.
  Future<ModelActivationResult> setActive(
    String modelId, {
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  });

  Future<void> remove(String modelId);
}
