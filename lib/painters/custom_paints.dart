import 'dart:math';
import 'package:flutter/material.dart';

class SpectrumPainter extends CustomPainter {
  final List<double> bars;
  SpectrumPainter({required this.bars});
  @override
  void paint(Canvas canvas, Size size) {
    final int barCount = bars.length;
    final double spacing = 3.0,
        barWidth = (size.width - (spacing * (barCount - 1))) / barCount,
        segmentHeight = 4.0,
        segmentSpacing = 1.0;
    for (int i = 0; i < barCount; i++) {
      final int segments =
          ((size.height * bars[i]) / (segmentHeight + segmentSpacing)).floor();
      for (int j = 0; j < segments; j++) {
        Color segmentColor = Colors.green;
        double ratio = j / (size.height / (segmentHeight + segmentSpacing));
        if (ratio > 0.7)
          segmentColor = Colors.red;
        else if (ratio > 0.4)
          segmentColor = Colors.orange;
        final paint = Paint()
          ..color = segmentColor
          ..style = PaintingStyle.fill;
        final borderPaint = Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        final rect = Rect.fromLTWH(
          i * (barWidth + spacing),
          size.height - (j * (segmentHeight + segmentSpacing)) - segmentHeight,
          barWidth,
          segmentHeight,
        );
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class WaveformPainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final double complexity;
  final Color color;

  WaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.complexity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    for (double x = 0; x <= width; x += 2.0) {
      double y =
          centerY +
          sin((x * complexity) + phase) *
              (height * amplitude) *
              cos((x * (complexity * 0.6)) - (phase * 0.5));

      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y.clamp(3.0, height - 3.0));
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.complexity != complexity ||
        oldDelegate.color != color;
  }
}

class CRTGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 4.0)
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 4.0)
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
