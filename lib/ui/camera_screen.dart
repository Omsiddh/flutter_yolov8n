import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detection_result.dart';
import '../services/isolate_manager.dart';
import 'hud_overlay.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  IsolateManager? _isolateManager;
  List<DetectionResult> _detections = [];
  bool _isDetecting = false;
  double _fps = 0.0;
  int _frameCount = 0;
  int _lastFrameTime = 0;
  
  // Performance Mode
  bool _lowPerformanceMode = false;
  int _frameSkipCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied')),
        );
      }
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No cameras found')),
        );
      }
      return;
    }

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.medium, // 720x480 or similar usually good balance
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      await _startIsolate();
      
      if (mounted) {
        setState(() {});
        _startImageStream();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<void> _startIsolate() async {
    _isolateManager = IsolateManager();
    await _isolateManager!.start();
    _isolateManager!.resultsStream.listen((results) {
      if (!mounted) return;
      setState(() {
        _detections = results;
        _isDetecting = false;
        
        // Calculate FPS
        _frameCount++;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastFrameTime >= 1000) {
          _fps = _frameCount / ((now - _lastFrameTime) / 1000);
          _frameCount = 0;
          _lastFrameTime = now;
          
          // Auto-enable low performance mode if FPS drops below 5
          if (_fps < 5 && !_lowPerformanceMode) {
             // _lowPerformanceMode = true; // Optional: auto-switch
          }
        }
      });
    });
  }

  void _startImageStream() {
    _controller!.startImageStream((CameraImage image) {
      if (_isDetecting) return;
      
      if (_lowPerformanceMode) {
        _frameSkipCounter++;
        if (_frameSkipCounter % 2 != 0) return;
      }

      _isDetecting = true;
      _isolateManager!.processCameraImage(image);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _isolateManager?.stop();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle camera lifecycle
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller != null) {
         _initializeCamera();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;
    
    // Scale preview to fit screen
    var scale = size.aspectRatio * _controller!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: scale,
            child: Center(
              child: CameraPreview(_controller!),
            ),
          ),
          HUDOverlay(
            detections: _detections,
            previewSize: _controller!.value.previewSize!,
            screenSize: size, // Provide screen size for overlay scaling
            fps: _fps,
          ),
          Positioned(
            bottom: 30,
            left: 20,
            child: Row(
               children: [
                   Switch(
                       value: _lowPerformanceMode, 
                       onChanged: (val) {
                           setState(() {
                               _lowPerformanceMode = val;
                           });
                       }
                   ),
                   const Text("Low Perf Mode", style: TextStyle(color: Colors.white, shadowBy: [Shadow(offset: Offset(1,1), blurRadius: 2)])),
               ],
            ),
          )
        ],
      ),
    );
  }
}
