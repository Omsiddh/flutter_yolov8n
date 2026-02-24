import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../models/detection_result.dart';
import 'tflite_service.dart';

class IsolateManager {
  static const String _debugName = 'InferenceIsolate';
  
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  
  StreamController<List<DetectionResult>>? _resultsStreamController;
  Stream<List<DetectionResult>> get resultsStream => _resultsStreamController!.stream;

  bool _isReady = false;

  Future<void> start() async {
    _receivePort = ReceivePort();
    _resultsStreamController = StreamController<List<DetectionResult>>.broadcast();

    RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    
    _isolate = await Isolate.spawn(
      _entryPoint,
      _InitPacket(
        _receivePort!.sendPort, 
        rootIsolateToken
      ),
      debugName: _debugName,
    );

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isReady = true;
      } else if (message is List<DetectionResult>) {
        _resultsStreamController?.add(message);
      }
    });
  }

  void processCameraImage(CameraImage image) {
    if (!_isReady || _sendPort == null) return;
    
    // We cannot pass CameraImage directly effectively because checks/pointers. 
    // We pass the raw bytes.
    // Making a copy of the bytes is necessary because the camera buffer might be reused.
    // However, copying is expensive. 
    // For now, let's pass a structure that contains the necessary plane bytes.
    
    final data = _CameraImagePacket.fromCameraImage(image);
    _sendPort!.send(data);
  }

  void stop() {
    _isolate?.kill();
    _receivePort?.close();
    _resultsStreamController?.close();
    _isReady = false;
  }

  static void _entryPoint(_InitPacket initPacket) async {
    final mainSendPort = initPacket.sendPort;
    final receivePort = ReceivePort();
    
    // Initialize background isolate
    if (initPacket.rootToken != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(initPacket.rootToken!);
    }
    
    final tfliteService = TFLiteService();
    try {
      await tfliteService.loadModels();
    } catch (e) {
      print('Failed to load models in isolate: $e');
      return; 
    }

    // Send the sendPort back to the main isolate
    mainSendPort.send(receivePort.sendPort);

    await for (final message in receivePort) {
      if (message is _CameraImagePacket) {
        try {
          // 1. Convert CameraImagePacket to Image
          // This is a placeholder. 
          // Real implementation requires robust YUV conversion in the isolate.
          // Due to complexity, we will assume a simplified flow or use a util.
          
          // For now, let's just create a dummy result to test pipeline if conversion fails
          // But we should try to include image logic.
          // Since we can't easily import 'image' package in snippet without file context, 
          // we will structure the call to TFLiteService.
          
          final results = tfliteService.runInferenceOnFrameYUV(
             message.bytes, 
             message.height, 
             message.width,
             message.uvRowStride,
             message.uvPixelStride
          );
          
          mainSendPort.send(results);
          
        } catch (e) {
          print('Error in inference loop: $e');
        }
      }
    }
    
    tfliteService.dispose();
  }
}

class _InitPacket {
  final SendPort sendPort;
  final RootIsolateToken? rootToken;
  _InitPacket(this.sendPort, this.rootToken);
}

class _CameraImagePacket {
  final List<Uint8List> bytes; // y, u, v planes
  final int height;
  final int width;
  final int uvRowStride;
  final int uvPixelStride;

  _CameraImagePacket({
    required this.bytes,
    required this.height,
    required this.width,
    required this.uvRowStride,
    required this.uvPixelStride,
  });

  factory _CameraImagePacket.fromCameraImage(CameraImage image) {
     return _CameraImagePacket(
       bytes: image.planes.map((plane) => Uint8List.fromList(plane.bytes)).toList(),
       height: image.height,
       width: image.width,
       uvRowStride: image.planes[1].bytesPerRow,
       uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
     );
  }
}
