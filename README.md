# AI Vision HUD - Real-time Detection & Depth Estimation

A Flutter application demonstrating simultaneous Object Detection (YOLOv8n) and Monocular Depth Estimation (Depth Anything V2) using TFLite.

## Features
- **Real-time Object Detection**: Uses YOLOv8n (Float16) to detect 80 classes of objects.
- **Monocular Depth Estimation**: Uses Depth Anything V2 to estimate relative depth per pixel.
- **Distance Estimation**: Combines bounding boxes with depth maps to estimate distance.
- **High Performance**: Runs inference in a background isolate to maintain 10+ FPS.
- **HUD Overlay**: Custom painter visualizing bounding boxes, labels, and distance.
- **Low Performance Mode**: Automatic frame skipping if FPS drops below 5.

## Setup

1. **Models Placement**:
   Ensure the following model files are present in the `ai_models/` directory at the project root:
   - `ai_models/yolov8n_float16.tflite`
   - `ai_models/depth_anything_v2.tflite`

   *Note: If you move them to an `assets/` folder, update `pubspec.yaml` and `lib/services/tflite_service.dart` accordingly.*

2. **Dependencies**:
   Run `flutter pub get` to install dependencies.

3. **Permissions**:
   - **Android**: Camera permission is added to `AndroidManifest.xml`.
   - **iOS**: Camera usage description is added to `Info.plist`.

4. **Run**:
   Connect a device and run:
   ```bash
   flutter run --release
   ```
   *Note: Use `--release` mode for best performance. Debug mode is significantly slower due to Dart VM overhead.*

## Architecture
- **Camera Stream**: Captures YUV420 frames.
- **Isolate**: Converts YUV to RGB, preprocesses images, and runs TFLite inference off the UI thread.
- **TFLite Service**: Manages Interpreter lifecycle and post-processing (NMS).
- **HUD**: Draws results over the camera preview.

## Requirements
- Flutter SDK ^3.11.0
- Device with Camera
- Android 5.0+ / iOS 11.0+
