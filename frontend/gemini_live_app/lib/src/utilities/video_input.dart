import 'dart:developer';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class VideoInput extends ChangeNotifier {
  late List<CameraDescription> _cameras;
  CameraController? _cameraController;

  StreamController<Uint8List>? _imageStreamController;

  bool _isStreaming = false;
  bool _initialized = false;
  bool get isInitialized => _initialized;
  bool _processingFrame = false;

  int _lastFrameTime = 0;

  Future<void> init() async {
    // Idempotent: only initialize once; call dispose() first to reinitialize.
    if (_initialized) return;
    try {
      _cameras = await availableCameras();

      _cameraController = CameraController(
        _cameras[0],
        ResolutionPreset.medium, // medium gives better inference quality than low
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      _initialized = true;
      notifyListeners();
      log('[VideoInput] Camera initialized: ${_cameras[0].name}');
    } catch (e) {
      log('[VideoInput] Camera init error: $e');
      rethrow;
    }
  }

  /// Returns the underlying [CameraController].
  /// Throws [StateError] if not yet initialized.
  CameraController get cameraController {
    if (!_initialized || _cameraController == null) {
      throw StateError(
          '[VideoInput] cameraController accessed before initialization.');
    }
    return _cameraController!;
  }

  Stream<Uint8List> startStreamingImages({int minIntervalMs = 250}) {
    // Guard: must be initialized before streaming
    if (!_initialized || _cameraController == null) {
      throw StateError(
          '[VideoInput] startStreamingImages() called before init().');
    }

    // If already streaming, return existing stream
    if (_isStreaming && _imageStreamController != null) {
      return _imageStreamController!.stream;
    }

    _imageStreamController?.close();
    _imageStreamController = StreamController<Uint8List>.broadcast();

    _isStreaming = true;
    _processingFrame = false;
    _lastFrameTime = 0;

    // Guard: don't call startImageStream if already streaming at camera level
    if (!_cameraController!.value.isStreamingImages) {
      _cameraController!.startImageStream((CameraImage image) async {
        if (_processingFrame) return;
        if (!_isStreaming) return;

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastFrameTime < minIntervalMs) return;

        _lastFrameTime = now;
        _processingFrame = true;

        try {
          final jpeg = await compute(_convertYuvParamsToJpeg, _YuvParams(
            width: image.width,
            height: image.height,
            yBytes: image.planes[0].bytes,
            uBytes: image.planes[1].bytes,
            vBytes: image.planes[2].bytes,
            yRowStride: image.planes[0].bytesPerRow,
            uRowStride: image.planes[1].bytesPerRow,
            vRowStride: image.planes[2].bytesPerRow,
            uPixelStride: image.planes[1].bytesPerPixel ?? 1,
            vPixelStride: image.planes[2].bytesPerPixel ?? 1,
          ));
          if (_isStreaming &&
              _imageStreamController != null &&
              !_imageStreamController!.isClosed) {
            _imageStreamController!.add(jpeg);
          }
        } catch (e) {
          log('[VideoInput] Frame conversion error: $e');
        } finally {
          _processingFrame = false;
        }
      });
    }

    return _imageStreamController!.stream;
  }

  Future<void> stopStreamingImages() async {
    if (!_isStreaming) return;

    _isStreaming = false;

    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      log('[VideoInput] stopImageStream error: $e');
    }

    await _imageStreamController?.close();
    _imageStreamController = null;

    _processingFrame = false;
  }

  @override
  void dispose() {
    _imageStreamController?.close();
    _imageStreamController = null;

    if (_initialized && _cameraController != null) {
      _cameraController!.dispose();
    }
    _initialized = false;

    super.dispose();
  }
}

class _YuvParams {
  final int width;
  final int height;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uRowStride;
  final int vRowStride;
  final int uPixelStride;
  final int vPixelStride;

  _YuvParams({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uRowStride,
    required this.vRowStride,
    required this.uPixelStride,
    required this.vPixelStride,
  });
}

Uint8List _convertYuvParamsToJpeg(_YuvParams params) {
  final int width = params.width;
  final int height = params.height;

  final imgBuffer = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int yIndex = y * params.yRowStride + x;

      final int uvRow = y >> 1;
      final int uvCol = x >> 1;
      final int uIndex = uvRow * params.uRowStride + uvCol * params.uPixelStride;
      final int vIndex = uvRow * params.vRowStride + uvCol * params.vPixelStride;

      final int yVal = params.yBytes[yIndex];
      final int uVal = params.uBytes[uIndex] - 128;
      final int vVal = params.vBytes[vIndex] - 128;

      final int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
      final int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
      final int b = (yVal + 1.772 * uVal).round().clamp(0, 255);

      imgBuffer.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  return Uint8List.fromList(img.encodeJpg(imgBuffer, quality: 75));
}