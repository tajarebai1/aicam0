import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/constants/app_constants.dart';
import 'package:safezone_mobile/features/detection/domain/detection_result.dart';
import 'package:safezone_mobile/features/models/domain/model_entry.dart';
import 'package:safezone_mobile/features/safety/domain/safety_policy.dart';
import 'package:safezone_mobile/features/safety/domain/safety_status.dart';

void main() {
  const policy = MaskSafetyPolicy();
  const profile = ModelProfile(
    id: 'p1',
    modelId: 'm1',
    profileName: 'default',
    classMapping: AppConstants.defaultMaskClassMapping,
    confidenceThreshold: 0.50,
    iouThreshold: 0.45,
    minEvidenceFrames: 3,
    maxGapMs: 600,
    createdAt: '2026-11-18T00:00:00Z',
  );
  const box = BoundingBox(left: 0.2, top: 0.2, right: 0.6, bottom: 0.6);

  group('P03 — Safety Policy (T11, T19)', () {
    test('maps with_mask to compliant', () {
      final decision = policy.decide(
        const [DetectionItem(classIndex: 0, label: 'with_mask', confidence: 0.88, box: box)],
        profile,
      );
      expect(decision.status, SafetyStatus.compliant);
    });

    test('maps without_mask and mask_weared_incorrect to violation', () {
      final d1 = policy.decide(
        const [DetectionItem(classIndex: 1, label: 'without_mask', confidence: 0.80, box: box)],
        profile,
      );
      final d2 = policy.decide(
        const [DetectionItem(classIndex: 2, label: 'mask_weared_incorrect', confidence: 0.72, box: box)],
        profile,
      );
      expect(d1.status, SafetyStatus.violation);
      expect(d2.status, SafetyStatus.violation);
    });

    test('returns REVIEW on marginal confidence or conflicting overlapping detections', () {
      final lowConf = policy.decide(
        const [DetectionItem(classIndex: 0, label: 'with_mask', confidence: 0.42, box: box)],
        profile,
      );
      expect(lowConf.status, SafetyStatus.review);

      final conflict = policy.decide(
        const [
          DetectionItem(classIndex: 0, label: 'with_mask', confidence: 0.75, box: box),
          DetectionItem(classIndex: 1, label: 'without_mask', confidence: 0.74, box: box),
        ],
        profile,
      );
      expect(conflict.status, SafetyStatus.review);
    });

    test('returns noConfirmedEvent when no face is visible', () {
      final empty = policy.decide(const [], profile);
      expect(empty.status, SafetyStatus.noConfirmedEvent);
    });
  });
}
