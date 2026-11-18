import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/constants/app_constants.dart';
import 'package:safezone_mobile/features/detection/domain/detection_result.dart';
import 'package:safezone_mobile/features/gate/domain/gate_analyzer.dart';
import 'package:safezone_mobile/features/gate/domain/gate_episode.dart';
import 'package:safezone_mobile/features/models/domain/model_entry.dart';
import 'package:safezone_mobile/features/safety/domain/safety_policy.dart';
import 'package:safezone_mobile/features/safety/domain/safety_status.dart';

void main() {
  const profile = ModelProfile(
    id: 'p1',
    modelId: 'm1',
    profileName: 'default',
    classMapping: AppConstants.defaultMaskClassMapping,
    confidenceThreshold: 0.45,
    iouThreshold: 0.45,
    minEvidenceFrames: 3,
    maxGapMs: 600,
    createdAt: '2026-11-18T00:00:00Z',
  );
  const centerBox = BoundingBox(left: 0.35, top: 0.30, right: 0.65, bottom: 0.70);

  FrameDetectionResult makeFrame(int offsetMs, String? label, {double conf = 0.85}) {
    return FrameDetectionResult(
      timestampUtc: DateTime.utc(2026, 11, 18, 12, 0, 0).add(Duration(milliseconds: offsetMs)),
      inferenceMs: 25.0,
      accelerator: AcceleratorType.cpu,
      detections: label == null
          ? const []
          : [DetectionItem(classIndex: 0, label: label, confidence: conf, box: centerBox)],
    );
  }

  group('P05 — Gate Mode Processor (T14, T15)', () {
    test('Reference scenario T14: 3 passages (2 violations + 1 compliant) produce 3 unique events', () {
      final processor = GateModeProcessor(
        safetyPolicy: const MaskSafetyPolicy(),
        config: const GateModeConfig(minEvidenceFrames: 3, maxGapMs: 600),
      );
      final events = <GatePassageEvent>[];

      // Passage 1: without_mask (4 frames)
      for (int i = 0; i < 4; i++) {
        final ev = processor.consumeDetection(makeFrame(i * 100, 'without_mask'), profile);
        if (ev != null) events.add(ev);
      }

      // Gap > 600ms -> Passage 2: mask_weared_incorrect (4 frames)
      for (int i = 0; i < 4; i++) {
        final ev = processor.consumeDetection(
          makeFrame(1500 + i * 100, 'mask_weared_incorrect'),
          profile,
        );
        if (ev != null) events.add(ev);
      }

      // Gap > 600ms -> Passage 3: with_mask (4 frames)
      for (int i = 0; i < 4; i++) {
        final ev = processor.consumeDetection(
          makeFrame(3000 + i * 100, 'with_mask'),
          profile,
        );
        if (ev != null) events.add(ev);
      }

      final last = processor.finishEpisode();
      if (last != null) events.add(last);

      expect(events.length, 3);
      expect(events[0].status, SafetyStatus.violation);
      expect(events[1].status, SafetyStatus.violation);
      expect(events[2].status, SafetyStatus.compliant);

      final summary = processor.summarize();
      expect(summary.totalPassages, 3);
      expect(summary.violationPassages, 2);
      expect(summary.compliantPassages, 1);
      expect(summary.reviewPassages, 0);
    });

    test('Insufficient evidence frames produce REVIEW instead of fabricating compliance', () {
      final processor = GateModeProcessor(
        safetyPolicy: const MaskSafetyPolicy(),
        config: const GateModeConfig(minEvidenceFrames: 3, maxGapMs: 600),
      );

      processor.consumeDetection(makeFrame(0, 'with_mask'), profile);
      processor.consumeDetection(makeFrame(100, 'with_mask'), profile);
      final ev = processor.finishEpisode();

      expect(ev, isNotNull);
      expect(ev!.status, SafetyStatus.review);
    });
  });
}
