import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';

class SquareCameraPreview extends StatelessWidget {
  const SquareCameraPreview({required this.controller, super.key});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: AspectRatio(
                aspectRatio: 1,
                child: Transform.scale(
                  scale: controller.value.aspectRatio / 1,
                  child: Center(child: CameraPreview(controller)),
                ),
              ),
            ),
          ),
          // HUD Elements
          Positioned(
            top: 16,
            left: 16,
            child: _HudMarker(color: Theme.of(context).colorScheme.secondary),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: RotatedBox(
              quarterTurns: 2,
              child: _HudMarker(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
        ],
      ),
    );
  }
}

class FullCameraPreview extends StatefulWidget {
  const FullCameraPreview({required this.controller, super.key});
  final CameraController controller;

  @override
  State<FullCameraPreview> createState() => _FullCameraPreviewState();
}

class _FullCameraPreviewState extends State<FullCameraPreview>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(32)),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: CameraPreview(widget.controller),
            ),
          ),
          // Floating HUD Label
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ).animate(onPlay: (c) => c.repeat())
                   .fadeIn(duration: 500.ms).fadeOut(delay: 500.ms),
                  const SizedBox(width: 8),
                  Text(
                    "VISION ACTIVE",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate(controller: _animController).scaleXY(begin: 0.9, end: 1.0).fadeIn();
  }
}

class _HudMarker extends StatelessWidget {
  final Color color;
  const _HudMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color, width: 2),
          left: BorderSide(color: color, width: 2),
        ),
      ),
    );
  }
}
