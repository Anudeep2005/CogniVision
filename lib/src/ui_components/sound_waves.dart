import 'dart:math';
import 'package:flutter/material.dart';

class CenterCircle extends StatelessWidget {
  const CenterCircle({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: const Size(160, 160),
        painter: NestedCirclesPainter(
          color: Theme.of(context).colorScheme.primary,
          strokeWidth: 1.0,
          gapBetweenCircles: 4.0,
        ),
        child: child,
      ),
    );
  }
}

class NestedCirclesPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gapBetweenCircles;

  NestedCirclesPainter({
    this.color = Colors.white54,
    this.strokeWidth = 1.5,
    this.gapBetweenCircles = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final double outerRadius =
        min(size.width / 2, size.height / 2) - strokeWidth / 2;
    final double innerRadius =
        outerRadius - gapBetweenCircles - strokeWidth / 2;

    if (innerRadius > 0) {
      canvas.drawCircle(center, outerRadius, paint);
      canvas.drawCircle(center, innerRadius, paint);
    } else {
      canvas.drawCircle(center, outerRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is NestedCirclesPainter &&
        (oldDelegate.color != color ||
            oldDelegate.strokeWidth != strokeWidth ||
            oldDelegate.gapBetweenCircles != gapBetweenCircles);
  }
}