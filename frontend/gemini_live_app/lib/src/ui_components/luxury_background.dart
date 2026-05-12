import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
          // Blurred Blobs
          Positioned(
            top: -100,
            right: -50,
            child: _Blob(
              color: const Color(0xFFCFE7DA).withOpacity(0.5),
              size: 300,
            ),
          ),
          Positioned(
            bottom: 100,
            left: -50,
            child: _Blob(
              color: const Color(0xFFD4B06A).withOpacity(0.1),
              size: 400,
            ),
          ),
          // Faint Gold Particles (Mockup with subtle dots)
          const IgnorePointer(
            child: Opacity(
              opacity: 0.05,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                        'https://www.transparenttextures.com/patterns/stardust.png'),
                    repeat: ImageRepeat.repeat,
                  ),
                ),
                child: SizedBox.expand(),
              ),
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
