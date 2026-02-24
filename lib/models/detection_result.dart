import 'dart:ui';

class DetectionResult {
  final String label;
  final double score;
  final Rect boundingBox;
  final double distance;

  DetectionResult({
    required this.label,
    required this.score,
    required this.boundingBox,
    required this.distance,
  });
}
