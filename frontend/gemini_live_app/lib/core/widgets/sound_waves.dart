import 'dart:math';
import 'package:flutter/material.dart';

import 'package:flutter_animate/flutter_animate.dart';

class CenterCircle extends StatelessWidget {
  const CenterCircle({required this.child, super.key, this.isListening = false, this.isSpeaking = false});
  final Widget child;
  final bool isListening;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final color = isListening 
        ? const Color(0xFF1F5C45) // Emerald
        : isSpeaking 
            ? const Color(0xFF2F6E56) 
            : const Color(0xFFC8A96B); // Gold (Thinking/Idle)

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer Glow Layer 1
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.15),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 3.seconds, curve: Curves.easeInOut),

          // Middle Ring
          CustomPaint(
            size: const Size(180, 180),
            painter: NestedCirclesPainter(
              color: color.withValues(alpha: 0.3),
              strokeWidth: 1.0,
            ),
          ).animate(onPlay: (c) => c.repeat())
           .rotate(duration: 10.seconds),

          // Inner Glowing Ring
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 2.seconds, curve: Curves.easeInOut),

          child,
        ],
      ),
    );
  }
}

class NestedCirclesPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  NestedCirclesPainter({
    this.color = Colors.white54,
    this.strokeWidth = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Draw a dashed or segmented ring for more "tech" feel
    const int segments = 8;
    const double sweepAngle = (2 * pi) / segments;
    for (int i = 0; i < segments; i++) {
      if (i % 2 == 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: size.width / 2),
          i * sweepAngle,
          sweepAngle * 0.7,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is NestedCirclesPainter && oldDelegate.color != color;
  }
}
