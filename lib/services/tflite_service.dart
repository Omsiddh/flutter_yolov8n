import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection_result.dart';

class IsolateData {
  final CameraImage cameraImage;
  final SendPort sendPort;
  final RootIsolateToken rootIsolateToken;

  IsolateData({
    required this.cameraImage,
    required this.sendPort,
    required this.rootIsolateToken,
  });
}

class TFLiteService {
  static const String yoloModelPath = 'ai_models/yolov8n_float16.tflite';
  static const String depthModelPath = 'ai_models/depth_anything_v2.tflite';

  Interpreter? _yoloInterpreter;
  Interpreter? _depthInterpreter;

  // YOLO Config
  static const int _yoloInputSize = 640;
  static const int _numClasses = 80; // COCO
  static const double _scoreThreshold = 0.45;
  static const double _iouThreshold = 0.5;

  // Depth Config
  static const int _depthInputSize = 518;

  // Labels for COCO dataset (standard 80 classes)
  static const List<String> _labels = [
    'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat', 'traffic light',
    'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
    'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee',
    'skis', 'snowboard', 'sports ball', 'kite', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard',
    'tennis racket', 'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
    'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake', 'chair', 'couch',
    'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse', 'remote', 'keyboard', 'cell phone',
    'microwave', 'oven', 'toaster', 'sink', 'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear',
    'hair drier', 'toothbrush'
  ];

  Future<void> loadModels() async {
    try {
      // GPU Delegate options
      final options = InterpreterOptions();
      if (Platform.isAndroid) {
         options.addDelegate(GpuDelegateV2());
      } else if (Platform.isIOS) {
         // options.addDelegate(GpuDelegate()); // Metal delegate is implicit or requires specific setup
      }
      
      // Load YOLO
      _yoloInterpreter = await Interpreter.fromAsset(yoloModelPath, options: options);
      log('YOLO Model loaded successfully');

      // Load Depth
      _depthInterpreter = await Interpreter.fromAsset(depthModelPath, options: options);
      log('Depth Model loaded successfully');
      
    } catch (e) {
      log('Error loading models: $e');
      throw Exception('Failed to load models: $e');
    }
  }

  List<DetectionResult> runInference(img.Image image) {
    if (_yoloInterpreter == null || _depthInterpreter == null) {
      log('Interpreter not initialized');
      return [];
    }

    // 1. Preprocessing for YOLO
    final yoloInput = _preprocessForYOLO(image);
    
    // 2. Preprocessing for Depth
    final depthInput = _preprocessForDepth(image);

    // 3. Inference
    // YOLO Output: [1, 84, 8400] -> Transpose to [1, 8400, 84] often needed or handle directly
    // The typical output shape is [1, 4 + 80, 8400]
    final yoloOutputBuffer = List.filled(1 * 84 * 8400, 0.0);
    // Depth Output: [1, 518, 518]
    final depthOutputBuffer = List.filled(1 * 518 * 518, 0.0); 

    // Re-shape for interpreter if needed, flat buffers are safer for raw copy
    // Let's use flexible buffers
    var yoloOutput = List.generate(1, (i) => List.generate(84, (j) => List.filled(8400, 0.0)));
    var depthOutput = List.generate(1, (i) => List.filled(518 * 518, 0.0));

    _yoloInterpreter!.run(yoloInput, yoloOutput);
    _depthInterpreter!.run(depthInput, depthOutput);

    // 4. Postprocessing
    // Parse YOLO results
    List<DetectionResult> detections = _postprocessYOLO(yoloOutput, image.width, image.height);

    // Map Depth to Detections
    // The depth output is usually inverse depth or relative depth. 
    // We need to verify if the model output is metric. Depth Anything V2 is relative depth.
    // However, for the user requirement "human-readable distance (meters)", we might need calibration.
    // Without calibration, we can only provide relative depth. 
    // But let's assume a simple mapping or interpret the output as disparity.
    // For this task, getting the raw value and assuming a conversion factor is a reasonable placeholder.
    _addDepthToDetections(detections, depthOutput[0], image.width, image.height);

    return detections;
  }

  /// Runs inference on YUV data (from CameraImage)
  List<DetectionResult> runInferenceOnFrameYUV(
    List<Uint8List> bytes, 
    int height, 
    int width,
    int uvRowStride,
    int uvPixelStride,
  ) {
    // Basic YUV conversion. For production, use 'image' package optimized functions 
    // or FFI. Here we implement a basic conversion for demonstration.
    final img.Image image = img.Image(width: width, height: height);

    // Access planes
    final yPlane = bytes[0];
    final uPlane = bytes[1];
    final vPlane = bytes[2];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * width + x;
        final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        if (yIndex >= yPlane.length || uvIndex >= uPlane.length || uvIndex >= vPlane.length) continue;

        final int yp = yPlane[yIndex];
        final int up = uPlane[uvIndex];
        final int vp = vPlane[uvIndex];

        // YUV to RGB conversion
        int r = (yp + 1.402 * (vp - 128)).round().clamp(0, 255);
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round().clamp(0, 255);
        int b = (yp + 1.772 * (up - 128)).round().clamp(0, 255);
        
        image.setPixelRgb(x, y, r, g, b);
      }
    }

    return runInference(image);
  }

  // --- Helper Methods ---

  List<List<List<double>>> _preprocessForYOLO(img.Image image) {
    // Resize to 640x640
    final resized = img.copyResize(image, width: _yoloInputSize, height: _yoloInputSize);
    
    // Normalize to [0, 1]
    var input = List.generate(1, (i) => List.generate(_yoloInputSize, (y) => List.generate(_yoloInputSize, (x) {
      final pixel = resized.getPixel(x, y);
      return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
    })));

    // Flatten logic might differ based on model input shape [1, 640, 640, 3]
    return input; // Currently returns [1, 640, 640, 3] structure
  }
  
  // Note: This is an expensive operation in Dart. 
  // In a real app, we should use FFI or optimize this loop.
  // The provided code is illustrative of logic.
  List<Object> _preprocessForDepth(img.Image image) {
    // Resize to 518x518
    final resized = img.copyResize(image, width: _depthInputSize, height: _depthInputSize);
    
    // Normalize (mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    var input = List.generate(1, (i) => List.generate(_depthInputSize, (y) => List.generate(_depthInputSize, (x) {
      final pixel = resized.getPixel(x, y);
      double r = (pixel.r / 255.0 - 0.485) / 0.229;
      double g = (pixel.g / 255.0 - 0.456) / 0.224;
      double b = (pixel.b / 255.0 - 0.406) / 0.225;
      return [r, g, b];
    })));
    return input;
  }

  List<DetectionResult> _postprocessYOLO(List<List<List<double>>> output, int imageWidth, int imageHeight) {
    // output shape: [1, 84, 8400]
    // 84 rows: 4 (x, y, w, h) + 80 classes
    // 8400 columns: number of anchors
    
    final List<DetectionResult> results = [];
    final int rows = 8400; 
    final int dimensions = 84; 

    // We need to transpose effectively or access by column
    // The output[0][dim][row]
    
    for (int i = 0; i < rows; i++) {
        // Find max score for classes
        double maxScore = 0.0;
        int classIndex = -1;
        
        for (int c = 0; c < _numClasses; c++) {
            double score = output[0][c + 4][i];
            if (score > maxScore) {
                maxScore = score;
                classIndex = c;
            }
        }

        if (maxScore > _scoreThreshold) {
            // Get box
            double cx = output[0][0][i];
            double cy = output[0][1][i];
            double w = output[0][2][i];
            double h = output[0][3][i];

            // Convert to [left, top, right, bottom]
            double left = (cx - w / 2) * imageWidth / _yoloInputSize;
            double top = (cy - h / 2) * imageHeight / _yoloInputSize;
            double right = (cx + w / 2) * imageWidth / _yoloInputSize;
            double bottom = (cy + h / 2) * imageHeight / _yoloInputSize;

            results.add(DetectionResult(
                label: _labels[classIndex],
                score: maxScore,
                boundingBox: Rect.fromLTRB(left, top, right, bottom),
                distance: 0.0, // Placeholder
            ));
        }
    }

    return _nms(results);
  }
  
  List<DetectionResult> _nms(List<DetectionResult> list) {
    List<DetectionResult> result = [];
    list.sort((a, b) => b.score.compareTo(a.score));

    while (list.isNotEmpty) {
      DetectionResult current = list.first;
      result.add(current);
      list.removeAt(0);
      list.removeWhere((other) => _iou(current.boundingBox, other.boundingBox) > _iouThreshold);
    }
    return result;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.width < 0 || intersection.height < 0) return 0;
    final unionArea = a.width * a.height + b.width * b.height - intersection.width * intersection.height;
    return (intersection.width * intersection.height) / unionArea;
  }

  void _addDepthToDetections(List<DetectionResult> detections, List<double> depthMap, int imageWidth, int imageHeight) {
      // depthMap is 518x518 flattened
      // Map bounding box to 518x518
      
      for (int i = 0; i < detections.length; i++) {
          var det = detections[i];
          
          // Scale bbox to depth map size
          int x1 = (det.boundingBox.left * _depthInputSize / imageWidth).round().clamp(0, _depthInputSize - 1);
          int y1 = (det.boundingBox.top * _depthInputSize / imageHeight).round().clamp(0, _depthInputSize - 1);
          int x2 = (det.boundingBox.right * _depthInputSize / imageWidth).round().clamp(0, _depthInputSize - 1);
          int y2 = (det.boundingBox.bottom * _depthInputSize / imageHeight).round().clamp(0, _depthInputSize - 1);
          
          if (x2 <= x1 || y2 <= y1) continue;

          List<double> values = [];
          for (int y = y1; y < y2; y++) {
              for (int x = x1; x < x2; x++) {
                  values.add(depthMap[y * _depthInputSize + x]);
              }
          }
          
          if (values.isNotEmpty) {
              values.sort();
              double medianDepth = values[values.length ~/ 2];
              
              // Map relative depth to meters. 
              // Without intrinsic parameters and known scale, this is a heuristic.
              // Assuming model output is somewhat inverse to distance or a direct relative metric.
              // Let's use a dummy calibration: distance = 1.0 / medianDepth (if inverse) or just scale it.
              // Depth Anything typically outputs relative disparity/depth.
              
              // Heuristic: invert and scale. Adjust '10.0' based on real world tests.
              // If output is disparity:
              double estimatedDistance = 0.0;
              if (medianDepth > 0) {
                 estimatedDistance = 100.0 / medianDepth; // Example conversion
              }
              
              detections[i] = DetectionResult(
                  label: det.label,
                  score: det.score,
                  boundingBox: det.boundingBox,
                  distance: estimatedDistance,
              );
          }
      }
  }

  void dispose() {
    _yoloInterpreter?.close();
    _depthInterpreter?.close();
  }
}
