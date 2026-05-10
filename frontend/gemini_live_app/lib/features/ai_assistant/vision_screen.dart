import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:vision_aid_app/core/services/voice_engine.dart';
import 'package:vision_aid_app/core/services/gemini_service.dart';
import 'package:vision_aid_app/features/ai_assistant/yolo_detector.dart';
import 'package:vision_aid_app/core/services/face_recognition_service.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vision_aid_app/features/ai_assistant/vision_provider.dart';

class VisionScreen extends ConsumerStatefulWidget {
  const VisionScreen({super.key});

  @override
  ConsumerState<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends ConsumerState<VisionScreen> {
  CameraController? _cameraController;
  final YoloDetector _yoloDetector = YoloDetector();
  bool _isProcessing = false;
  bool _isCameraReady = false;
  List<DetectionResult> _lastDetections = [];

  @override
  void initState() {
    super.initState();
    _initVision();
  }

  Future<void> _initVision() async {
    try {
      await _yoloDetector.init();
      await faceRecognitionService.init();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        await voiceEngine.speak('No camera found on this device.');
        return;
      }

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      // Register controller for global access
      ref.read(cameraControllerProvider.notifier).state = _cameraController;

      setState(() {
        _isCameraReady = true;
      });

      await voiceEngine.speak('Vision mode activated. Scanning surroundings.');

      // We will use a Timer to take pictures instead of startImageStream to avoid memory issues and complex YUV conversion
      _startPeriodicScan();

    } catch (e) {
      debugPrint('Vision Init Error: $e');
      await voiceEngine.speak('Failed to initialize vision system.');
    }
  }

  Timer? _scanTimer;

  void _startPeriodicScan() {
    _scanTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (_isProcessing || !_cameraController!.value.isInitialized) return;
      _isProcessing = true;

      try {
        final XFile file = await _cameraController!.takePicture();
        final bytes = await file.readAsBytes();

        // 1. YOLO Object Detection
        final detections = await _yoloDetector.detect(bytes);
        if (mounted) {
          setState(() {
            _lastDetections = detections;
          });
        }

        if (detections.isNotEmpty) {
          final labels = detections.map((d) => d.label).toSet().join(', ');
          await voiceEngine.speak('I see $labels');
        }

        // 2. Face Recognition
        final inputImage = InputImage.fromFilePath(file.path);
        final faces = await faceRecognitionService.detectFaces(inputImage);
        
        if (faces.isNotEmpty) {
           await voiceEngine.speak('Detected ${faces.length} people.');
           
           for (final face in faces) {
             final embedding = await faceRecognitionService.getEmbedding(face, bytes);
             if (embedding != null) {
               final name = faceRecognitionService.identifyFace(embedding);
               if (name != null) {
                 await voiceEngine.speak('I see $name');
               }
             }
           }
        }

      } catch (e) {
        debugPrint('Scan Error: $e');
      } finally {
        _isProcessing = false;
      }
    });
  }

  Future<void> _describeScene() async {
    if (!_cameraController!.value.isInitialized) return;
    
    await voiceEngine.speak('Analyzing scene...');
    try {
      final XFile file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();
      
      final description = await geminiService.analyzeImage(bytes, 'Describe the scene in front of me clearly and concisely for a visually impaired person. Mention any hazards or important objects.');
      await voiceEngine.speak(description);
      
    } catch (e) {
      await voiceEngine.speak('Sorry, I could not analyze the scene.');
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraController?.dispose();
    _yoloDetector.dispose();
    // Clear global reference safely
    Future.microtask(() {
      if (mounted) {
        ref.read(cameraControllerProvider.notifier).state = null;
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for actions from CommandRouter
    ref.listen(visionActionProvider, (previous, next) {
      if (next == VisionAction.describe) {
        _describeScene();
        // Reset action after triggering
        Future.microtask(() {
           ref.read(visionActionProvider.notifier).state = VisionAction.none;
        });
      }
    });

    if (!_isCameraReady || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          
          // Bounding Boxes Overlay
          CustomPaint(
            painter: BoundingBoxPainter(_lastDetections),
          ),

          // Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton.large(
                  heroTag: 'describe',
                  onPressed: _describeScene,
                  backgroundColor: const Color(0xFF1F5C45),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 40),
                ),
                FloatingActionButton(
                  heroTag: 'close',
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<DetectionResult> detections;
  BoundingBoxPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var d in detections) {
      // boundingBox is [cx, cy, w, h] normalized [0..1]
      final rect = Rect.fromCenter(
        center: Offset(d.boundingBox[0] * size.width, d.boundingBox[1] * size.height),
        width: d.boundingBox[2] * size.width,
        height: d.boundingBox[3] * size.height,
      );
      canvas.drawRect(rect, paint);

      textPainter.text = TextSpan(
        text: d.label,
        style: const TextStyle(color: Colors.white, backgroundColor: Colors.green, fontSize: 16),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, rect.top - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
