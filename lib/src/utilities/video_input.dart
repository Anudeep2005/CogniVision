import 'dart:developer';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image/image.dart' as img;

class VideoInput extends ChangeNotifier {
  late List<CameraDescription> _cameras;
  late CameraController _cameraController;

  StreamController<Uint8List>? _imageStreamController;

  bool _isStreaming = false;
  bool _initialized = false;
  bool _processingFrame = false;

  int _lastFrameTime = 0;

  Future<void> init() async {
    try {
      _cameras = await availableCameras();

      _cameraController = CameraController(
        _cameras[0],
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController.initialize();
      _initialized = true;
      notifyListeners();
    } catch (e) {
      log("Camera init error: $e");
    }
  }

  CameraController get cameraController => _cameraController;

  Stream<Uint8List> startStreamingImages() {
    if (_isStreaming && _imageStreamController != null) {
      return _imageStreamController!.stream;
    }

    // Always create a fresh StreamController each session
    _imageStreamController?.close();
    _imageStreamController = StreamController<Uint8List>.broadcast();

    _isStreaming = true;
    _processingFrame = false;
    _lastFrameTime = 0;

    _cameraController.startImageStream((CameraImage image) async {
      if (_processingFrame) return;
      if (!_isStreaming) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      // 1 frame per second — enough for Gemini, low overhead
      if (now - _lastFrameTime < 1000) return;

      _lastFrameTime = now;
      _processingFrame = true;

      try {
        final jpeg = await _convertYuv420ToJpeg(image);
        if (_isStreaming && 
            _imageStreamController != null && 
            !_imageStreamController!.isClosed) {
          _imageStreamController!.add(jpeg);
        }
      } catch (e) {
        log("Frame conversion error: $e");
      } finally {
        _processingFrame = false;
      }
    });

    return _imageStreamController!.stream;
  }

  /// Proper YUV420 → RGB → JPEG conversion using all 3 planes
  Future<Uint8List> _convertYuv420ToJpeg(CameraImage image) async {
    final int width = image.width;
    final int height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final imgBuffer = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * yPlane.bytesPerRow + x;

        // U and V planes are subsampled 2x in both directions
        final int uvRow = y >> 1;
        final int uvCol = x >> 1;
        final int uIndex = uvRow * uPlane.bytesPerRow + uvCol * uPlane.bytesPerPixel!;
        final int vIndex = uvRow * vPlane.bytesPerRow + uvCol * vPlane.bytesPerPixel!;

        final int yVal = yPlane.bytes[yIndex];
        final int uVal = uPlane.bytes[uIndex] - 128;
        final int vVal = vPlane.bytes[vIndex] - 128;

        // BT.601 YUV → RGB
        int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
        int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
        int b = (yVal + 1.772 * uVal).round().clamp(0, 255);

        imgBuffer.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return Uint8List.fromList(img.encodeJpg(imgBuffer, quality: 60));
  }

  Future<void> stopStreamingImages() async {
    if (!_isStreaming) return;

    _isStreaming = false;

    try {
      if (_cameraController.value.isStreamingImages) {
        await _cameraController.stopImageStream();
      }
    } catch (e) {
      log("stopImageStream error: $e");
    }

    // Close and null out the stream controller so next session gets a fresh one
    await _imageStreamController?.close();
    _imageStreamController = null;

    _processingFrame = false;
  }

  @override
  void dispose() {
    _imageStreamController?.close();
    _imageStreamController = null;

    if (_initialized) {
      _cameraController.dispose();
    }

    super.dispose();
  }
}