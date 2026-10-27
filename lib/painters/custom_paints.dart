import 'dart:math';
import 'package:flutter/material.dart';

/// Estado partilhado entre o visualizador e os painters. Notifica apenas o
/// [CustomPaint] (via `repaint`), sem reconstruir widgets.
class VisualizerModel extends ChangeNotifier {
  final List<double> bars;
  double phase = 0.0;
  double amplitude = 0.05;
  double complexity = 0.02;

  VisualizerModel({required int barCount}) : bars = List.filled(barCount, 0.1);

  void markChanged() => notifyListeners();
}

class SpectrumPainter extends CustomPainter {
  final VisualizerModel model;
  SpectrumPainter({required this.model}) : super(repaint: model);

  static final Paint _green = Paint()..color = Colors.green;
  static final Paint _orange = Paint()..color = Colors.orange;
  static final Paint _red = Paint()..color = Colors.red;
  static final Paint _border = Paint()
    ..color = Colors.black87
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = model.bars;
    final int barCount = bars.length;
    const double spacing = 3.0, segmentHeight = 4.0, segmentSpacing = 1.0;
    final double barWidth =
        (size.width - (spacing * (barCount - 1))) / barCount;
    final double maxSegments = size.height / (segmentHeight + segmentSpacing);
    for (int i = 0; i < barCount; i++) {
      final int segments =
          ((size.height * bars[i]) / (segmentHeight + segmentSpacing)).floor();
      for (int j = 0; j < segments; j++) {
        final double ratio = j / maxSegments;
        final paint = ratio > 0.7
            ? _red
            : ratio > 0.4
            ? _orange
            : _green;
        final rect = Rect.fromLTWH(
          i * (barWidth + spacing),
          size.height - (j * (segmentHeight + segmentSpacing)) - segmentHeight,
          barWidth,
          segmentHeight,
        );
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect, _border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) =>
      oldDelegate.model != model;
}

class WaveformPainter extends CustomPainter {
  final VisualizerModel model;
  final Color color;

  WaveformPainter({required this.model, required this.color})
    : super(repaint: model);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final phase = model.phase;
    final amplitude = model.amplitude;
    final complexity = model.complexity;
    final path = Path();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    for (double x = 0; x <= width; x += 2.0) {
      final double y =
          centerY +
          sin((x * complexity) + phase) *
              (height * amplitude) *
              cos((x * (complexity * 0.6)) - (phase * 0.5));
      if (x == 0) {
        path.moveTo(x, y.clamp(3.0, height - 3.0));
      } else {
        path.lineTo(x, y.clamp(3.0, height - 3.0));
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.model != model || oldDelegate.color != color;
}

class CRTGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 4.0) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 4.0) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
