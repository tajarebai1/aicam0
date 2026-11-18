# SafeZone AI Mobile — Architecture (Baseline v1)

## Target

- Flutter/Dart app: Arabic RTL, Android, Galaxy Z Flip3.
- Kotlin only for native integration when current verified Flutter plugin cannot satisfy the requirement.
- Native LiteRT inference: first attempt official Ultralytics Flutter plugin, behind a replaceable engine adapter.
- Training/export on Google Colab, never in the APK.
- One Android app-private SQLite database: `safezone_mobile.db`. Model files are outside SQLite.

## Layer boundaries

`CameraSource` → `InferenceEngine` → `DetectionResult` → `SafetyPolicy` → Live UI / `GateAnalyzer` → ephemeral counters / opt-in metadata logs.

1. **Camera**: sole owner of one live camera session; controls permissions, preview, rotation, app lifecycle, foldable transitions. Never open Flutter camera and native YOLOView simultaneously.
2. **Models**: import through system picker; copy to app-private storage; checksum, inspect metadata, validate tensors, smoke-test on actual device before activation.
3. **Detection**: adapts native plugin outputs into normalized timestamp, label, score and box information. Must not retain frames.
4. **Safety**: maps model labels into `compliant`, `violation`, `review`; never invents confidence when face is not visible.
5. **Gate**: aggregates evidence per face episode; marks real verified crossings only if tested tracking/line-crossing evidence exists. No identity recognition.
6. **Settings/Storage**: one source for active model and preferences; historical event logging disabled by default.

## Key interfaces

- `CameraSource`: `start()`, `stop()`, `switchLens()`, `observeFrame()`.
- `ModelRepository`: `importModel()`, `listModels()`, `validate()`, `setActive()`, `remove()`.
- `InferenceEngine`: `load()`, `warmup()`, `infer()`, `switchModel()`, `dispose()`.
- `SafetyPolicy`: `decide(detections, profile) → status, reason, evidence`.
- `GateAnalyzer`: `consumeDetection()`, `finishEpisode()`, `summarize()`.
- `SessionRepository`: optional event logs only with explicit consent.

## Privacy design

No photo/video saving, face embeddings, face recognition, cloud transfer or automatic person identification. Use in-memory live counters unless the user opts into storing anonymous event metadata. Optional retention and delete policy required before collecting histories.

## Database and migrations

Read `safezone_mobile_schema.sql`. Create tables gradually through versioned migrations, rather than executing all tables during Phase 0. Phase P2: model registry, profiles, settings, checks. Phase P4: benchmarking optional. Phase P6: sessions/events optional. Database and models remain stable through app version changes.

## Quality gates

Each stage requires actual command results and (where applicable) on-device tests before manual acceptance. Check UI plugin APIs against the installed package version. Avoid copying outdated code examples blindly.
