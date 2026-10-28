import 'dart:async';
import 'dart:developer';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────────────────────
// Frame carriers
// ─────────────────────────────────────────────────────────────────────────────

/// Packed, upright RGB frame (`width × height × 3`, row-major, R-G-B).
class RawFrame {
  final Uint8List rgbBytes;
  final int width;
  final int height;

  /// Kept for API compatibility. Frames produced by [yuvToUprightRgb] are
  /// already rotated upright, so this is 0 for them.
  final int rotation;

  const RawFrame({
    required this.rgbBytes,
    required this.width,
    required this.height,
    this.rotation = 0,
  });
}

/// One camera frame exactly as Android delivers it (YUV420, sensor
/// orientation). Nothing is converted here: the plane buffers are only
/// referenced, so creating a [YuvFrame] is free.
///
/// [rotation] is the clockwise angle (0/90/180/270) that turns the sensor
/// image upright in a portrait-held phone (= the camera's sensorOrientation).
class YuvFrame {
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int width;
  final int height;
  final int yRowStride;
  final int uRowStride;
  final int vRowStride;
  final int uPixelStride;
  final int vPixelStride;
  final int rotation;

  const YuvFrame({
    required this.y,
    required this.u,
    required this.v,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uRowStride,
    required this.vRowStride,
    required this.uPixelStride,
    required this.vPixelStride,
    required this.rotation,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// VideoInput
// ─────────────────────────────────────────────────────────────────────────────

/// Owns the single [CameraController] of the Vertex tab.
///
/// Design rules (these exist to avoid the CameraX "too many use cases" crash):
///  * The native image stream is started ONCE and never stopped/restarted while
///    the camera is open. Switching between YOLO and Gemini only changes which
///    consumer receives frames, so CameraX never re-binds use cases.
///  * Every start/stop/init/release goes through one serial queue, so two
///    callers can never touch the camera at the same time.
///  * [release] fully disposes the controller. Call it when the app goes to the
///    background or the tab becomes inactive, and call [init] again afterwards.
class VideoInput extends ChangeNotifier {
  List<CameraDescription> _cameras = const [];
  CameraController? _cameraController;
  int _sensorOrientation = 90;

  bool _initialized = false;
  bool _disposed = false;

  // Consumers (broadcast controllers live until dispose()).
  StreamController<Uint8List>? _jpegController;
  StreamController<YuvFrame>? _yuvController;

  bool _jpegActive = false;
  bool _yuvActive = false;
  bool _jpegBusy = false;
  int _jpegIntervalMs = 1000;
  int _yuvIntervalMs = 200;
  int _lastJpegMs = 0;
  int _lastYuvMs = 0;

  // Serial operation queue.
  Future<void> _opTail = Future<void>.value();

  bool get isInitialized => _initialized && _cameraController != null;

  /// Clockwise degrees needed to make a sensor frame upright (portrait phone).
  int get sensorOrientation => _sensorOrientation;

  CameraController get cameraController {
    final controller = _cameraController;
    if (!_initialized || controller == null) {
      throw StateError(
          '[VideoInput] cameraController accessed before initialization.');
    }
    return controller;
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _opTail = _opTail.then((_) async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Opens the back camera. Idempotent; safe to call repeatedly.
  Future<void> init() => _serial<void>(_initLocked);

  Future<void> _initLocked() async {
    if (_disposed) return;
    if (_initialized && _cameraController != null) return;
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        throw StateError('No cameras found on this device.');
      }

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      _sensorOrientation = camera.sensorOrientation;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();

      _cameraController = controller;
      _initialized = true;
      _notify();
      log('[VideoInput] Camera initialized: ${camera.name} '
          '(sensorOrientation=$_sensorOrientation)');
    } catch (e) {
      log('[VideoInput] Camera init error: $e');
      rethrow;
    }
  }

  /// Stops the image stream and fully disposes the camera.
  /// Call when the app is backgrounded or the Vertex tab becomes inactive.
  Future<void> release() => _serial<void>(() async {
        _jpegActive = false;
        _yuvActive = false;
        _jpegBusy = false;
        final controller = _cameraController;
        _cameraController = null;
        _initialized = false;
        await _shutdownController(controller);
        _notify();
        log('[VideoInput] Camera released');
      });

  static Future<void> _shutdownController(CameraController? controller) async {
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      log('[VideoInput] stopImageStream error: $e');
    }
    try {
      await controller.dispose();
    } catch (e) {
      log('[VideoInput] controller dispose error: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Consumers ─────────────────────────────────────────────────────────────

  /// JPEG frames (upright) for Gemini Live.
  Future<Stream<Uint8List>> startStreamingImages(
      {int minIntervalMs = 1000}) async {
    _jpegController ??= StreamController<Uint8List>.broadcast();
    _jpegIntervalMs = minIntervalMs;
    _lastJpegMs = 0;
    _jpegActive = true;
    try {
      await _ensureImageStream();
    } catch (e) {
      _jpegActive = false;
      rethrow;
    }
    return _jpegController!.stream;
  }

  /// Raw YUV frames for on-device YOLO. Zero conversion work happens here.
  Future<Stream<YuvFrame>> startStreamingYuvFrames(
      {int minIntervalMs = 200}) async {
    _yuvController ??= StreamController<YuvFrame>.broadcast();
    _yuvIntervalMs = minIntervalMs;
    _lastYuvMs = 0;
    _yuvActive = true;
    try {
      await _ensureImageStream();
    } catch (e) {
      _yuvActive = false;
      rethrow;
    }
    return _yuvController!.stream;
  }

  /// Stops delivering frames to every consumer. The camera and its native
  /// image stream stay open on purpose (no CameraX re-binding). Use
  /// [release] to actually free the camera.
  Future<void> stopStreamingImages() async {
    _jpegActive = false;
    _yuvActive = false;
  }

  Future<void> _ensureImageStream() => _serial<void>(() async {
        final controller = _cameraController;
        if (controller == null || !_initialized) {
          throw StateError('[VideoInput] start*() called before init().');
        }
        if (controller.value.isStreamingImages) return;
        await controller.startImageStream(_onCameraImage);
      });

  // ── Per-frame callback (runs on the main isolate – keep it tiny) ──────────

  void _onCameraImage(CameraImage image) {
    if (_disposed) return;

    final yuvCtl = _yuvController;
    final jpegCtl = _jpegController;
    final bool wantYuv = _yuvActive && yuvCtl != null && !yuvCtl.isClosed;
    final bool wantJpeg =
        _jpegActive && !_jpegBusy && jpegCtl != null && !jpegCtl.isClosed;
    if (!wantYuv && !wantJpeg) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    final bool yuvDue = wantYuv && now - _lastYuvMs >= _yuvIntervalMs;
    final bool jpegDue = wantJpeg && now - _lastJpegMs >= _jpegIntervalMs;
    if (!yuvDue && !jpegDue) return;

    final planes = image.planes;
    if (planes.length < 3) return; // not a 3-plane YUV frame

    final frame = YuvFrame(
      y: planes[0].bytes,
      u: planes[1].bytes,
      v: planes[2].bytes,
      width: image.width,
      height: image.height,
      yRowStride: planes[0].bytesPerRow,
      uRowStride: planes[1].bytesPerRow,
      vRowStride: planes[2].bytesPerRow,
      uPixelStride: planes[1].bytesPerPixel ?? 1,
      vPixelStride: planes[2].bytesPerPixel ?? 1,
      rotation: _sensorOrientation,
    );

    if (yuvDue) {
      _lastYuvMs = now;
      yuvCtl!.add(frame);
    }
    if (jpegDue) {
      _lastJpegMs = now;
      _jpegBusy = true;
      unawaited(_encodeJpeg(frame));
    }
  }

  Future<void> _encodeJpeg(YuvFrame frame) async {
    try {
      // 1 fps → a throw-away isolate per frame is cheap and keeps the UI free.
      final jpeg = await compute(_yuvFrameToJpeg, frame);
      final ctl = _jpegController;
      if (_jpegActive && !_disposed && ctl != null && !ctl.isClosed) {
        ctl.add(jpeg);
      }
    } catch (e) {
      log('[VideoInput] JPEG encode error: $e');
    } finally {
      _jpegBusy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _jpegActive = false;
    _yuvActive = false;

    final controller = _cameraController;
    _cameraController = null;
    _initialized = false;
    unawaited(_shutdownController(controller));

    _jpegController?.close();
    _jpegController = null;
    _yuvController?.close();
    _yuvController = null;

    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversion (top-level: usable from compute())
// ─────────────────────────────────────────────────────────────────────────────

int _normalizeRotation(int degrees) =>
    ((((degrees % 360) + 360) % 360) ~/ 90) * 90;

/// YUV420 → upright packed RGB. Integer BT.601; rotates clockwise by
/// [YuvFrame.rotation] while converting (no extra pass).
RawFrame yuvToUprightRgb(YuvFrame f) {
  final int w = f.width;
  final int h = f.height;
  final int rot = _normalizeRotation(f.rotation);
  final bool transposed = rot == 90 || rot == 270;
  final int ow = transposed ? h : w;
  final int oh = transposed ? w : h;

  final Uint8List rgb = Uint8List(ow * oh * 3);
  int o = 0;

  for (int oy = 0; oy < oh; oy++) {
    for (int ox = 0; ox < ow; ox++) {
      final int x;
      final int y;
      if (!transposed) {
        x = rot == 0 ? ox : w - 1 - ox;
        y = rot == 0 ? oy : h - 1 - oy;
      } else {
        x = rot == 90 ? oy : w - 1 - oy;
        y = rot == 90 ? h - 1 - ox : ox;
      }

      final int yv = f.y[y * f.yRowStride + x];
      final int uvRow = y >> 1;
      final int uvCol = x >> 1;
      final int uv = f.u[uvRow * f.uRowStride + uvCol * f.uPixelStride] - 128;
      final int vv = f.v[uvRow * f.vRowStride + uvCol * f.vPixelStride] - 128;

      final int r = yv + ((1436 * vv) >> 10);
      final int g = yv - ((352 * uv + 731 * vv) >> 10);
      final int b = yv + ((1815 * uv) >> 10);

      rgb[o++] = r < 0 ? 0 : (r > 255 ? 255 : r);
      rgb[o++] = g < 0 ? 0 : (g > 255 ? 255 : g);
      rgb[o++] = b < 0 ? 0 : (b > 255 ? 255 : b);
    }
  }

  return RawFrame(rgbBytes: rgb, width: ow, height: oh);
}

/// Gemini path: upright RGB → JPEG.
Uint8List _yuvFrameToJpeg(YuvFrame f) {
  final rgb = yuvToUprightRgb(f);
  final image = img.Image.fromBytes(
    width: rgb.width,
    height: rgb.height,
    bytes: rgb.rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  return img.encodeJpg(image, quality: 70);
}
