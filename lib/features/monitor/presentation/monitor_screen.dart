import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/app_controller.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../camera/domain/camera_source.dart';
import '../../camera/presentation/camera_preview_widget.dart';

class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final cam = controller.cameraSource;
    final activeModel = controller.activeModel;
    final perf = controller.perfSnapshot;
    final counters = controller.liveCounters;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active model & mode header
          Card(
            color: const Color(0xFF111827),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.memory, color: Color(0xFF38BDF8), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeModel != null
                              ? 'النموذج النشط: ${activeModel.displayName}'
                              : 'لا يوجد نموذج مفعّل بعد',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          controller.gateModeEnabled
                              ? 'الوضع: بوابة (Gate Mode — تجميع مرور)'
                              : 'الوضع: مراقبة حية مباشرة (Live)',
                          style: const TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      perf.accelerator.name.toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: const Color(0xFF1E293B),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Live safety status banner
          SafetyStatusBanner(
            status: controller.latestDecision.status,
            reason: controller.latestDecision.reason,
            confidence: controller.latestDecision.confidence,
            primaryLabel: controller.latestDecision.primaryLabel,
          ),
          const SizedBox(height: 12),

          // Camera Preview container (foldable-safe height)
          Container(
            height: 360,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1120),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: cam.isRunning && cam.controller != null
                ? CameraPreviewWithOverlay(
                    controller: cam.controller!,
                    detections: controller.latestDetections,
                    isFrontCamera: cam.currentLens == CameraLensChoice.front,
                    showGateRoi:
                        controller.gateModeEnabled && controller.gateRoiEnabled,
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_off_outlined,
                            size: 52,
                            color: Colors.white38,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            cam.lastError ?? 'الكاميرا متوقفة حالياً (لا يتم حفظ صور أو فيديو).',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          if (cam.permissionState ==
                              CameraPermissionState.permanentlyDenied) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: openAppSettings,
                              icon: const Icon(Icons.settings),
                              label: const Text('فتح إعدادات الصلاحيات'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),

          // Camera control buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: controller.isBusyAction
                      ? null
                      : () {
                          if (cam.isRunning) {
                            controller.stopCamera();
                          } else {
                            controller.startCamera();
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: cam.isRunning
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(cam.isRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(
                    cam.isRunning ? 'إيقاف المراقبة' : 'بدء المراقبة',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: (!cam.isRunning || controller.isBusyAction)
                    ? null
                    : controller.switchCameraLens,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: const Icon(Icons.cameraswitch),
                label: Text(
                  cam.currentLens == CameraLensChoice.front ? 'خلفية' : 'أمامية',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Live metrics strip
          Row(
            children: [
              _MiniStatCard(
                title: controller.gateModeEnabled ? 'مرور ملتزم' : 'إطارات ملتزمة',
                value: controller.gateModeEnabled
                    ? '${counters.gateCompliantPassages}'
                    : '${counters.liveCompliantFrames}',
                color: const Color(0xFF4ADE80),
              ),
              const SizedBox(width: 8),
              _MiniStatCard(
                title: controller.gateModeEnabled ? 'مرور مخالف' : 'إطارات مخالفة',
                value: controller.gateModeEnabled
                    ? '${counters.gateViolationPassages}'
                    : '${counters.liveViolationFrames}',
                color: const Color(0xFFF87171),
              ),
              const SizedBox(width: 8),
              _MiniStatCard(
                title: 'مراجعة',
                value: controller.gateModeEnabled
                    ? '${counters.gateReviewPassages}'
                    : '${counters.liveReviewFrames}',
                color: const Color(0xFFFBBF24),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Performance strip (P04)
          Card(
            color: const Color(0xFF111827),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _PerfMetric('معاينة FPS', perf.previewFps.toStringAsFixed(1)),
                  _PerfMetric('استدلال FPS', perf.inferenceFps.toStringAsFixed(1)),
                  _PerfMetric('p50 (ms)', perf.medianLatencyMs.toStringAsFixed(1)),
                  _PerfMetric('p95 (ms)', perf.p95LatencyMs.toStringAsFixed(1)),
                  _PerfMetric('إسقاط', '${perf.droppedFrames}'),
                ],
              ),
            ),
          ),

          if (controller.gateModeEnabled && controller.recentGatePassages.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'آخر حالات المرور المرصودة (وضع البوابة)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            ...controller.recentGatePassages.take(5).map(
              (ev) => Card(
                color: const Color(0xFF111827),
                child: ListTile(
                  dense: true,
                  title: Text(
                    'مرور #${ev.episodeNumber} — ${ev.status.arabicLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${ev.note} (${ev.durationMs} ms)',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    '${(ev.averageConfidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PerfMetric extends StatelessWidget {
  const _PerfMetric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF38BDF8),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }
}
