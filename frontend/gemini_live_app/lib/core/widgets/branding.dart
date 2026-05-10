import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AppTitle extends StatelessWidget {
  const AppTitle({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.0,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class LeafAppIcon extends StatelessWidget {
  const LeafAppIcon({this.size = 40, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 16),
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            color: Theme.of(context).colorScheme.primary,
            Icons.spa_rounded,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}

class LuxuryBackground extends StatelessWidget {
  const LuxuryBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7F2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF5F7F2),
            Color(0xFFEAF5EE),
            Color(0xFFDDEFE5),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: _Blob(
              color: const Color(0xFFCFE7DA).withValues(alpha: 0.5),
              size: 300,
            ),
          ),
          Positioned(
            bottom: 100,
            left: -50,
            child: _Blob(
              color: const Color(0xFFD4B06A).withValues(alpha: 0.1),
              size: 400,
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
        begin: const Offset(-20, -20),
        end: const Offset(20, 20),
        duration: 10.seconds,
        curve: Curves.easeInOut);
  }
}
