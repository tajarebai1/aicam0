# SafeZone AI Mobile (`safezone_mobile`)

تطبيق Android محلي (Offline-First) مبني بـ **Flutter + Dart** بواجهة عربية **RTL** لمراقبة الالتزام بارتداء الكمامة عبر نماذج **YOLO Detection (LiteRT / TFLite)** مع إمكانية استيراد وتبديل النماذج من داخل الهاتف دون إعادة بناء APK.

## الميزات المنفذة (المراحل P00 — P07)
- **P00 التأسيس:** هيكلية نظيفة (`app`, `core`, `features`, `shared`), وثائق معمارية (`docs/ARCHITECTURE.md`, `docs/MODEL_CONTRACT.md`, `docs/ROADMAP.md`, `docs/TEST_PLAN.md`, `docs/ADR/`), وقاعدة SQLite بترحيلات مرقّمة (`safezone_mobile.db`).
- **P01 الكاميرا والواجهة العربية:** مالك واحد لجلسة الكاميرا (`FlutterCameraSource`)، دعم الأمامية/الخلفية، تحرير تلقائي للموارد عند الخلفية أو طي Samsung Galaxy Z Flip3، بدون حفظ صور أو فيديو.
- **P02 مكتبة النماذج الديناميكية:** استيراد `.tflite` + `model.json` اختياري عبر Android SAF إلى التخزين الخاص، حساب SHA-256، منع التكرار، فحص التنسورات، اختبار دخاني (`smoke inference`)، وتبديل آمن مع **استرجاع تلقائي (Rollback)** عند الفشل.
- **P03 كشف الكمامات وسياسة السلامة:** ربط `with_mask` -> ملتزم، `without_mask` و`mask_weared_incorrect` -> مخالفة، وحالات عدم اليقين/التعارض -> `REVIEW`. يشمل سكربت Colab للتصدير (`tools/export_mask_v4_colab.py`).
- **P04 قياس الأداء والتحسين:** فصل Preview FPS عن Inference FPS، حساب Median (p50) وp95 Latency، آلية Backpressure (أحدث إطار فقط)، ودعم CPU وGPU Delegate مع الرجوع التلقائي إلى CPU.
- **P05 وضع البوابة (Gate Mode):** تجميع الأدلة عبر الإطارات (`GateModeProcessor`) لمنع تكرار احتساب نفس المرور، دعم نطاق الباب (Door ROI)، وحالة `REVIEW` عند نقص الأدلة.
- **P06 الإحصائيات والخصوصية:** عدادات حية داخل الذاكرة، سجل أحداث نصي مجهول الهوية **معطّل افتراضياً**، بدء جلسة جديدة دون حذف التاريخ، وتصدير CSV مجهول الهوية.
- **P07 الجاهزية والإصدار:** إعدادات Android (`com.safezone.ai.mobile`, `minSdk 26`, `targetSdk 34`) بدون صلاحية `INTERNET`، اختبارات وحدات شاملة، وتنبيهات التراخيص.

## خطوات التشغيل والتحقق على جهازك (Windows / Android)

```bash
cd safezone_mobile
flutter pub get
flutter analyze
flutter test
```

### تشغيل التطبيق على جهاز Samsung Galaxy Z Flip3 (أو أي جهاز Android 11+)
```bash
flutter devices
flutter run
```

### بناء ملف Release APK
```bash
flutter build apk --release
```
سيتم إنتاج الملف في: `build/app/outputs/flutter-apk/app-release.apk`.

## تصدير نموذج الكمامة (`best_mask_v4.pt`) عبر Google Colab
استخدم السكربت الجاهز في `tools/export_mask_v4_colab.py` لتصدير `.tflite` وتوليد `model.json` ثم انقلهما إلى الهاتف واستوردهما مباشرة من تبويب **النماذج** داخل التطبيق.

## الخصوصية والتراخيص
- راجع `docs/PRIVACY_AND_LICENSING.md` لمراجعة سياسة عدم حفظ الوسائط وتنبيه رخصة **Ultralytics AGPL-3.0**.
