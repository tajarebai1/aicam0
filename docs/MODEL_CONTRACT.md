# Dynamic Model Contract — SafeZone AI Mobile

## Scope

The first APK supports **compatible Ultralytics YOLO Detection** LiteRT/TFLite exports. The `.tflite` extension alone is not proof of compatibility. PyTorch `.pt` must be exported in Colab. Other output types or model families may require an additional adapter and thus a new APK.

## Import pipeline

1. Select a model using Android's system file picker (SAF).
2. Copy bytes to application-private storage, not to SQLite and not to shared temporary storage.
3. Calculate SHA-256 and identify duplicates.
4. Read embedded metadata; accept optional accompanying `model.json` for class mapping and version details.
5. Inspect actual input/output shapes, tensor layout, dtype, NMS, label count and task; reject contradictions.
6. Initialize a native compatible engine and perform successful smoke inference **on the device**.
7. Activate only on success; on failure return to the previous model and show a clear error.
8. Remember the working active model across app restarts and upgrades.

## Example manifest (not validated; placeholders must be replaced)

```json
{
  "schema_version": 1,
  "model_id": "mask-yolo11n-v4",
  "display_name": "SafeZone Mask Detector v4",
  "file_name": "mask_v4.tflite",
  "task": "detect",
  "family": "YOLO11n",
  "format": "tflite",
  "sha256": "<CALCULATE_AFTER_EXPORT>",
  "input": {
    "width": 640,
    "height": 640,
    "layout": "<INSPECT_ACTUAL_TENSOR>",
    "dtype": "<INSPECT_ACTUAL_TENSOR>",
    "color": "RGB",
    "normalization": "<VERIFY_EXPORT>"
  },
  "output": {
    "layout": "<INSPECT_ACTUAL_TENSOR>",
    "nms": "<VERIFY_EXPORT>"
  },
  "classes": {
    "0": "with_mask",
    "1": "without_mask",
    "2": "mask_weared_incorrect"
  },
  "mapping": {
    "with_mask": "compliant",
    "without_mask": "violation",
    "mask_weared_incorrect": "violation"
  },
  "export": {
    "tool": "Ultralytics",
    "version": "<PIN_REAL_VERSION>",
    "format": "<LITERT_OR_LEGACY_TFLITE>",
    "source_checkpoint": "best_mask_v4.pt"
  },
  "compatibility": {
    "runtime": "ultralytics_yolo",
    "plugin_version": "<PIN_TESTED_VERSION>",
    "tested_on": "Samsung Galaxy Z Flip3",
    "validated": false
  }
}
```

## Safety label mapping

- `with_mask → compliant`
- `without_mask → violation`
- `mask_weared_incorrect → violation`
- If no sufficient face evidence, conflict or incompatible classes: `review` or `no confirmed event`, according to the explicit product rule. Distinguish these in tests.

## Important compatibility risk

LiteRT exports produced by different Ultralytics versions/formats may use different input tensor layout and output/NMS conventions. Do **not** assume a newer `format="litert"` file has identical shape to a legacy `format="tflite"` model. Pin and record real package/export versions only after validating an actual model on Z Flip3.

## Future models

Helmet, gloves, multiple PPE detection require appropriate class maps, and Gate Mode may need a tracker or updated inference adapter. Never call an unknown model 'supported' without testing the native runtime.
