import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'video_input.dart' show RawFrame;

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class DetectionResult {
  final String label;
  final double confidence;
  final List<double> boundingBox; // [cx, cy, w, h] normalised 0.0–1.0

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  /// Named record for the UI painter: left/top/width/height all normalised.
  ({double left, double top, double width, double height}) get rect => (
        left: boundingBox[0] - boundingBox[2] / 2,
        top: boundingBox[1] - boundingBox[3] / 2,
        width: boundingBox[2],
        height: boundingBox[3],
      );

  /// Horizontal centre [0.0, 1.0].
  double get centerX => boundingBox[0];

  /// Horizontal screen zone: left / centre / right.
  String get spatialPosition {
    if (centerX < 0.33) return 'left';
    if (centerX > 0.66) return 'right';
    return 'centre';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Worker-isolate plumbing  (all top-level — required by Isolate.spawn)
// ─────────────────────────────────────────────────────────────────────────────

/// Persistent worker-isolate entry point.
/// Called once by [Isolate.spawn]; never called from application code.
void _yoloIsolateEntry(SendPort callerPort) {
  final myPort = ReceivePort();
  callerPort.send(myPort.sendPort); // hand back our own port

  Interpreter? interpreter;
  List<String>? labels;

  myPort.listen((dynamic msg) {
    if (msg is! Map<String, dynamic>) return;
    final type = msg['type'] as String;

    if (type == 'init') {
      final replyPort = msg['replyPort'] as SendPort;
      // ── Initialise the interpreter from raw model bytes ──────────────────
      try {
        final modelBytes = msg['modelBytes'] as Uint8List;
        labels = (msg['labels'] as List<dynamic>).cast<String>();
        interpreter = Interpreter.fromBuffer(modelBytes);
        replyPort.send(true);
      } catch (e) {
        replyPort.send('init_error:$e');
      }
    } else if (type == 'infer') {
      final replyPort = msg['replyPort'] as SendPort;
      // ── Run full inference synchronously (this is the worker isolate) ────
      if (interpreter == null || labels == null) {
        replyPort.send(<Map<String, dynamic>>[]);
        return;
      }
      try {
        final jpegBytes = msg['jpegBytes'] as Uint8List;
        final results =
            _isolateRunInference(interpreter!, labels!, jpegBytes);
        replyPort.send(results);
      } catch (e) {
        replyPort.send(<Map<String, dynamic>>[]);
      }
    } else if (type == 'infer_raw') {
      final replyPort = msg['replyPort'] as SendPort;
      // ── Raw-RGB path: no JPEG decode, direct pixel access ─────────────────
      if (interpreter == null || labels == null) {
        replyPort.send(<Map<String, dynamic>>[]);
        return;
      }
      try {
        final rgbBytes = msg['rgbBytes'] as Uint8List;
        final srcWidth  = msg['width']  as int;
        final srcHeight = msg['height'] as int;
        final results = _isolateRunInferenceRaw(
            interpreter!, labels!, rgbBytes, srcWidth, srcHeight);
        replyPort.send(results);
      } catch (e) {
        replyPort.send(<Map<String, dynamic>>[]);
      }
    } else if (type == 'shutdown') {
      interpreter?.close();
      myPort.close();
    }
  });
}

/// JPEG path — kept for backward compatibility (e.g. fallback / tests).
List<Map<String, dynamic>> _isolateRunInference(
  Interpreter interpreter,
  List<String> labels,
  Uint8List jpegBytes,
) {
  final image = img.decodeImage(jpegBytes);
  if (image == null) return [];
  return _isolateRunInferenceFromImage(interpreter, labels, image);
}

/// Raw-RGB path — eliminates the JPEG encode/decode round-trip.
///
/// [rgbBytes] is a packed `srcWidth × srcHeight × 3` buffer (R, G, B per
/// pixel, row-major) as produced by [VideoInput.startStreamingRawFrames].
List<Map<String, dynamic>> _isolateRunInferenceRaw(
  Interpreter interpreter,
  List<String> labels,
  Uint8List rgbBytes,
  int srcWidth,
  int srcHeight,
) {
  // Build an img.Image directly from the raw RGB bytes — no codec involved.
  final image = img.Image.fromBytes(
    width: srcWidth,
    height: srcHeight,
    bytes: rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  return _isolateRunInferenceFromImage(interpreter, labels, image);
}

/// Shared core: resize → NCHW tensor → run → parse.
List<Map<String, dynamic>> _isolateRunInferenceFromImage(
  Interpreter interpreter,
  List<String> labels,
  img.Image image,
) {
  // 1. Resize to 640×640
  final resized = img.copyResize(
    image,
    width: _kInputSize,
    height: _kInputSize,
    interpolation: img.Interpolation.linear,
  );

  // 2. Build NCHW [1, 3, 640, 640] nested list
  final inputTensor = <List<List<List<double>>>>[
    List.generate(
      3,
      (c) => List.generate(
        _kInputSize,
        (y) => List.generate(_kInputSize, (x) {
          final px = resized.getPixel(x, y);
          switch (c) {
            case 0:
              return px.r / 255.0;
            case 1:
              return px.g / 255.0;
            default:
              return px.b / 255.0;
          }
        }),
      ),
    )
  ];

  // 3. Output buffer [1, 84, 8400]
  final outputBuffer = <List<List<double>>>[
    List.generate(84, (_) => List<double>.filled(_kNumAnchors, 0.0))
  ];

  // 4. Run inference (blocks THIS isolate, not the main UI thread)
  interpreter.run(inputTensor, outputBuffer);

  // 5. Decode + NMS → serialisable maps
  return _parseToMaps(outputBuffer, labels);
}

List<Map<String, dynamic>> _parseToMaps(
  List<List<List<double>>> output,
  List<String> labels,
) {
  const confidenceThreshold = 0.25;
  const iouThreshold = 0.45;
  const maxDetections = 10;

  final int numClasses = labels.length;
  final batch = output[0]; // [84, 8400]

  final candidates = <Map<String, dynamic>>[];

  for (int i = 0; i < _kNumAnchors; i++) {
    double maxConf = 0.0;
    int classId = -1;

    for (int j = 0; j < numClasses; j++) {
      final conf = batch[4 + j][i];
      if (conf > maxConf) {
        maxConf = conf;
        classId = j;
      }
    }

    if (maxConf > confidenceThreshold && classId >= 0) {
      candidates.add({
        'label': labels[classId],
        'confidence': maxConf,
        'cx': (batch[0][i] / _kInputSize).clamp(0.0, 1.0),
        'cy': (batch[1][i] / _kInputSize).clamp(0.0, 1.0),
        'w': (batch[2][i] / _kInputSize).clamp(0.0, 1.0),
        'h': (batch[3][i] / _kInputSize).clamp(0.0, 1.0),
      });
    }
  }

  // Sort by confidence descending
  candidates
      .sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));

  // NMS
  final results = <Map<String, dynamic>>[];
  for (final c in candidates) {
    bool keep = true;
    for (final k in results) {
      if (_iouMaps(c, k) > iouThreshold) {
        keep = false;
        break;
      }
    }
    if (keep) results.add(c);
    if (results.length >= maxDetections) break;
  }

  return results;
}

double _iouMaps(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ax1 = (a['cx'] as double) - (a['w'] as double) / 2;
  final ay1 = (a['cy'] as double) - (a['h'] as double) / 2;
  final ax2 = (a['cx'] as double) + (a['w'] as double) / 2;
  final ay2 = (a['cy'] as double) + (a['h'] as double) / 2;

  final bx1 = (b['cx'] as double) - (b['w'] as double) / 2;
  final by1 = (b['cy'] as double) - (b['h'] as double) / 2;
  final bx2 = (b['cx'] as double) + (b['w'] as double) / 2;
  final by2 = (b['cy'] as double) + (b['h'] as double) / 2;

  final ix1 = ax1 > bx1 ? ax1 : bx1;
  final iy1 = ay1 > by1 ? ay1 : by1;
  final ix2 = ax2 < bx2 ? ax2 : bx2;
  final iy2 = ay2 < by2 ? ay2 : by2;

  final iw = ix2 - ix1;
  final ih = iy2 - iy1;
  if (iw <= 0 || ih <= 0) return 0.0;

  final intersection = iw * ih;
  final aArea = (a['w'] as double) * (a['h'] as double);
  final bArea = (b['w'] as double) * (b['h'] as double);
  final union = aArea + bArea - intersection;
  return union <= 0 ? 0.0 : intersection / union;
}

const int _kInputSize = 640;
const int _kNumAnchors = 8400;

// ─────────────────────────────────────────────────────────────────────────────
// YoloDetector — public API (unchanged from previous version)
// ─────────────────────────────────────────────────────────────────────────────

class YoloDetector {
  // Worker isolate state
  Isolate? _isolate;
  SendPort? _workerPort;
  bool _isolateReady = false;
  bool _isInferring = false;

  // Labels are kept on the main isolate for test access
  List<String>? _labels;

  // ── Public getters ────────────────────────────────────────────────────────

  bool get isInferring => _isInferring;
  bool get isInitialized => _isolateReady && _labels != null;

  /// Exposed for tests only.
  List<String>? get labels => _labels;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (isInitialized) return;
    try {
      // Load model bytes and labels on the main isolate (rootBundle available)
      final byteData =
          await rootBundle.load('assets/models/yolov8n.tflite');
      final modelBytes = byteData.buffer.asUint8List();

      final labelsRaw =
          await rootBundle.loadString('assets/models/yolov8n.txt');
      _labels =
          labelsRaw.split('\n').where((s) => s.trim().isNotEmpty).toList();

      // Spawn the persistent inference isolate
      final receivePort = ReceivePort();
      _isolate = await Isolate.spawn(
        _yoloIsolateEntry,
        receivePort.sendPort,
        debugName: 'YoloInferenceWorker',
      );

      // Wait for the worker to send back its SendPort
      _workerPort = await receivePort.first as SendPort;

      // Initialise the interpreter inside the worker
      final initReply = ReceivePort();
      _workerPort!.send(<String, dynamic>{
        'type': 'init',
        'modelBytes': modelBytes,
        'labels': _labels,
        'replyPort': initReply.sendPort,
      });
      final initResult = await initReply.first;
      initReply.close();

      if (initResult == true) {
        _isolateReady = true;
        debugPrint(
          '[YoloDetector] Worker isolate ready — ${_labels!.length} classes',
        );
      } else {
        throw Exception('[YoloDetector] Worker init failed: $initResult');
      }
    } catch (e) {
      debugPrint('[YoloDetector] Initialization error: $e');
      rethrow;
    }
  }

  void dispose() {
    _workerPort?.send(<String, dynamic>{'type': 'shutdown'});
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _isolateReady = false;
    _isInferring = false;
    _labels = null;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Runs detection on encoded JPEG bytes.
  /// Returns immediately if not ready or another inference is in-flight.
  Future<List<DetectionResult>> detect(Uint8List jpegBytes) async {
    if (!_isolateReady || _workerPort == null || _isInferring) return [];

    _isInferring = true;
    try {
      final replyPort = ReceivePort();
      _workerPort!.send(<String, dynamic>{
        'type': 'infer',
        'jpegBytes': jpegBytes,
        'replyPort': replyPort.sendPort,
      });

      final raw = await replyPort.first as List<dynamic>;
      replyPort.close();

      final results = raw
          .cast<Map<dynamic, dynamic>>()
          .map((m) => DetectionResult(
                label: m['label'] as String,
                confidence: m['confidence'] as double,
                boundingBox: [
                  m['cx'] as double,
                  m['cy'] as double,
                  m['w'] as double,
                  m['h'] as double,
                ],
              ))
          .toList();

      if (results.isNotEmpty) {
        debugPrint(
          '[YoloDetector] ${results.length} detection(s): '
          '${results.take(3).map((d) => '${d.label}('
              '${(d.confidence * 100).toStringAsFixed(0)}%,'
              '${d.spatialPosition})').join(', ')}',
        );
      }

      return results;
    } catch (e) {
      debugPrint('[YoloDetector] Inference error: $e');
      return [];
    } finally {
      _isInferring = false;
    }
  }

  /// Runs detection on a [RawFrame] (raw RGB pixel buffer).
  ///
  /// Preferred over [detect] for the YOLO live-camera path — it skips the
  /// JPEG encode/decode round-trip, reducing per-frame latency by ~40–80 ms
  /// and GC pressure by ~10 MB per frame.
  Future<List<DetectionResult>> detectRaw(RawFrame frame) async {
    if (!_isolateReady || _workerPort == null || _isInferring) return [];

    _isInferring = true;
    try {
      final replyPort = ReceivePort();
      _workerPort!.send(<String, dynamic>{
        'type': 'infer_raw',
        'rgbBytes': frame.rgbBytes,
        'width': frame.width,
        'height': frame.height,
        'replyPort': replyPort.sendPort,
      });

      final raw = await replyPort.first as List<dynamic>;
      replyPort.close();

      final results = raw
          .cast<Map<dynamic, dynamic>>()
          .map((m) => DetectionResult(
                label: m['label'] as String,
                confidence: m['confidence'] as double,
                boundingBox: [
                  m['cx'] as double,
                  m['cy'] as double,
                  m['w'] as double,
                  m['h'] as double,
                ],
              ))
          .toList();

      if (results.isNotEmpty) {
        debugPrint(
          '[YoloDetector] ${results.length} detection(s): '
          '${results.take(3).map((d) => '${d.label}('
              '${(d.confidence * 100).toStringAsFixed(0)}%,'
              '${d.spatialPosition})').join(', ')}',
        );
      }

      return results;
    } catch (e) {
      debugPrint('[YoloDetector] Raw inference error: $e');
      return [];
    } finally {
      _isInferring = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Static helpers — preserved unchanged for unit tests
  // ─────────────────────────────────────────────────────────────────────────

  /// Converts an [img.Image] to a nested NCHW [1, 3, 640, 640] float list.
  /// Exposed as static so widget tests can call it without a live device.
  static List<List<List<List<double>>>> preprocessImage(img.Image image) {
    final img.Image resized =
        (image.width == _kInputSize && image.height == _kInputSize)
            ? image
            : img.copyResize(image,
                width: _kInputSize,
                height: _kInputSize,
                interpolation: img.Interpolation.linear);

    return [
      List.generate(
        3,
        (c) => List.generate(
          _kInputSize,
          (y) => List.generate(_kInputSize, (x) {
            final pixel = resized.getPixel(x, y);
            switch (c) {
              case 0:
                return pixel.r / 255.0;
              case 1:
                return pixel.g / 255.0;
              default:
                return pixel.b / 255.0;
            }
          }),
        ),
      )
    ];
  }

  /// Decodes model output [1, 84, 8400] and applies NMS.
  /// Exposed as static so widget tests can exercise decoding logic directly.
  static List<DetectionResult> parseOutputs(
    List<List<List<double>>> output,
    List<String> labels, {
    double confidenceThreshold = 0.25,
    double iouThreshold = 0.45,
    int maxDetections = 10,
  }) {
    final int numClasses = labels.length;
    final batch = output[0];

    final candidates = <DetectionResult>[];

    for (int i = 0; i < _kNumAnchors; i++) {
      double maxConf = 0.0;
      int classId = -1;

      for (int j = 0; j < numClasses; j++) {
        final conf = batch[4 + j][i];
        if (conf > maxConf) {
          maxConf = conf;
          classId = j;
        }
      }

      if (maxConf > confidenceThreshold && classId >= 0 && classId < numClasses) {
        candidates.add(DetectionResult(
          label: labels[classId],
          confidence: maxConf,
          boundingBox: [
            (batch[0][i] / _kInputSize).clamp(0.0, 1.0),
            (batch[1][i] / _kInputSize).clamp(0.0, 1.0),
            (batch[2][i] / _kInputSize).clamp(0.0, 1.0),
            (batch[3][i] / _kInputSize).clamp(0.0, 1.0),
          ],
        ));
      }
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    final nmsResults = <DetectionResult>[];
    for (final res in candidates) {
      bool keep = true;
      for (final kept in nmsResults) {
        if (_calculateIoU(res.boundingBox, kept.boundingBox) > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) nmsResults.add(res);
      if (nmsResults.length >= maxDetections) break;
    }

    if (nmsResults.isNotEmpty) {
      debugPrint(
        '[YoloDetector] ${nmsResults.length} detection(s): '
        '${nmsResults.take(3).map((d) => '${d.label}('
            '${(d.confidence * 100).toStringAsFixed(0)}%,'
            '${d.spatialPosition})').join(', ')}',
      );
    }

    return nmsResults;
  }

  static double _calculateIoU(List<double> box1, List<double> box2) {
    final b1x1 = box1[0] - box1[2] / 2;
    final b1y1 = box1[1] - box1[3] / 2;
    final b1x2 = box1[0] + box1[2] / 2;
    final b1y2 = box1[1] + box1[3] / 2;

    final b2x1 = box2[0] - box2[2] / 2;
    final b2y1 = box2[1] - box2[3] / 2;
    final b2x2 = box2[0] + box2[2] / 2;
    final b2y2 = box2[1] + box2[3] / 2;

    final x1 = b1x1 > b2x1 ? b1x1 : b2x1;
    final y1 = b1y1 > b2y1 ? b1y1 : b2y1;
    final x2 = b1x2 < b2x2 ? b1x2 : b2x2;
    final y2 = b1y2 < b2y2 ? b1y2 : b2y2;

    final width = x2 - x1;
    final height = y2 - y1;
    if (width <= 0 || height <= 0) return 0.0;

    final intersection = width * height;
    final union =
        box1[2] * box1[3] + box2[2] * box2[3] - intersection;
    return union <= 0 ? 0.0 : intersection / union;
  }
}
