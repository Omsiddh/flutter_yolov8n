// lib/ui/hud_overlay.dart
import 'package:flutter/material.dart';
import '../models/detection_result.dart';

class HUDOverlay extends StatelessWidget {
  final List<DetectionResult> detections;
  final Size previewSize;
  final Size screenSize;
  final double fps;

  const HUDOverlay({
    super.key,
    required this.detections,
    required this.previewSize,
    required this.screenSize,
    required this.fps,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HUDPainter(
        detections: detections,
        previewSize: previewSize,
        screenSize: screenSize,
        fps: fps,
      ),
      child: Container(),
    );
  }
}

class _HUDPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Size previewSize;
  final Size screenSize;
  final double fps;

  _HUDPainter({
    required this.detections,
    required this.previewSize,
    required this.screenSize,
    required this.fps,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boxPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Paint textBgPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final TextStyle textStyle = TextStyle(
      color: Colors.cyanAccent,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );
    
    // Scale factor to map preview coordinates to screen coordinates
    // Assuming aspect ratio is preserved or handled by CameraPreview widget logic (usually BoxFit.cover or contain)
    // For simplicity, we assume the preview fills the screen width (portrait) or height.
    double scaleX = size.width / previewSize.width;
    double scaleY = size.height / previewSize.height;
    
    // Actually, camera preview usually rotates. 
    // If portrait: previewSize might be 480x640 (w,h) but screen is 360x(aspect aligned).
    // The raw coordinates from TFLite are relative to the image fed (w,h).
    // TFLiteService receives image width/height from camera stream.
    // If camera is portrait, the image is usually rotated 90 deg. 
    // For this MVP, let's assume we mapped coordinates to the display space correctly or we scale simply.
    // NOTE: CameraImage stream is landscape (usually). The UI is portrait.
    // We'll calculate scale based on assuming the input image was processed as-is.
    
    // Adjust scale for "cover" fit if needed, but 'contain' is safer for now.
    // Let's rely on passed screenSize vs previewSize
    
    for (var result in detections) {
      // Scale bounding box
      final Rect rect = result.boundingBox;
      
      // Coordinate transformation logic here depends on camera rotation.
      // Assuming standard mapping for now.
      final Rect scaledRect = Rect.fromLTRB(
        rect.left * scaleX,
        rect.top * scaleY,
        rect.right * scaleX,
        rect.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, boxPaint);

      // Label
      final String labelText = '${result.label} ${(result.score * 100).toStringAsFixed(0)}%\nDist: ${result.distance.toStringAsFixed(2)}m';
      final TextSpan span = TextSpan(text: labelText, style: textStyle);
      final TextPainter tp = TextPainter(
        text: span,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      );
      tp.layout();

      // Draw text background
      canvas.drawRect(
        Rect.fromLTWH(
          scaledRect.left,
          scaledRect.top - tp.height,
          tp.width + 4,
          tp.height,
        ),
        textBgPaint,
      );
      
      tp.paint(canvas, Offset(scaledRect.left + 2, scaledRect.top - tp.height));
    }

    // Draw FPS
    final String fpsText = 'FPS: ${fps.toStringAsFixed(1)}';
    final TextSpan fpsSpan = TextSpan(
      text: fpsText, 
      style: TextStyle(
          color: Colors.greenAccent, 
          fontSize: 18, 
          fontWeight: FontWeight.w900,
          shadows: [
              Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1,1))
          ]
      )
    );
    final TextPainter fpsTp = TextPainter(
      text: fpsSpan,
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );
    fpsTp.layout();
    fpsTp.paint(canvas, Offset(size.width - fpsTp.width - 20, 40));
  }

  @override
  bool shouldRepaint(covariant _HUDPainter oldDelegate) {
    return oldDelegate.detections != detections || oldDelegate.fps != fps;
  }
}
