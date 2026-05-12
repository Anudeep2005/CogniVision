import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraService {
  CameraController? controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      minFaceSize: 0.15,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) throw Exception('No cameras found');

    // Prefer front camera
    final frontCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await controller!.initialize();
    _isInitialized = true;
  }

  /// Detect faces in the current camera frame
  Future<List<Face>> detectFacesInImage(XFile imageFile) async {
    final inputImage = InputImage.fromFilePath(imageFile.path);
    return await _faceDetector.processImage(inputImage);
  }

  Future<XFile?> takePicture() async {
    if (controller == null || !controller!.value.isInitialized) return null;
    if (controller!.value.isTakingPicture) return null;
    try {
      return await controller!.takePicture();
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return null;
    }
  }

  void dispose() {
    _faceDetector.close();
    controller?.dispose();
    _isInitialized = false;
  }
}
