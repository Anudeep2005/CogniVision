import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';

class SquareCameraPreview extends StatelessWidget {
  const SquareCameraPreview({required this.controller, super.key});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 350,
        height: 350,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: Transform.scale(
              scale: controller.value.aspectRatio / 1,
              child: Center(child: CameraPreview(controller)),
            ),
          ),
        ),
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
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: CameraPreview(widget.controller),
      ),
    ).animate(controller: _animController).scaleXY().fadeIn();
  }
}