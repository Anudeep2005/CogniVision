import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class DetectionResult {
  final String label;
  final double confidence;
  final List<double> boundingBox; // [cx, cy, w, h] normalized to [0.0, 1.0]

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  // Helper for UI painting: returns [left, top, width, height] normalized
  ({double left, double top, double width, double height}) get rect {
    return (
      left: boundingBox[0] - (boundingBox[2] / 2),
      top: boundingBox[1] - (boundingBox[3] / 2),
      width: boundingBox[2],
      height: boundingBox[3],
    );
  }

  /// Horizontal centre [0.0, 1.0]. 
  double get centerX => boundingBox[0];

  /// Spatial direction based on horizontal centre.
  /// < 0.33 → left, > 0.66 → right, otherwise → centre.
  String get spatialPosition {
    if (centerX < 0.33) return 'left';
    if (centerX > 0.66) return 'right';
    return 'centre';
  }
}

class YoloDetector {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isInferring = false;

  // Model constants
  static const int _inputSize = 640;
  static const int _numAnchors = 8400;
  // numClasses derived from label file (80 for COCO)

  Interpreter? get interpreter => _interpreter;
  List<String>? get labels => _labels;
  bool get isInferring => _isInferring;
  bool get isInitialized => _interpreter != null && _labels != null;

  Future<void> init() async {
    if (isInitialized) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/yolov8n.tflite');
      final labelsData =
          await rootBundle.loadString('assets/models/yolov8n.txt');
      _labels =
          labelsData.split('\n').where((s) => s.trim().isNotEmpty).toList();

      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      debugPrint(
        '[YoloDetector] Initialized — ${_labels!.length} classes loaded. '
        'Input: ${inputTensor.shape} (${inputTensor.type}), '
        'Output: ${outputTensor.shape} (${outputTensor.type})',
      );
    } catch (e) {
      debugPrint('[YoloDetector] Initialization error: $e');
      rethrow;
    }
  }

  /// Converts an [img.Image] into a nested List<List<List<List<double>>>> 
  /// with shape [1, 3, 640, 640] (NCHW), values normalized to [0.0, 1.0].
  /// YOLOv8 ONNX→TFLite exports default to NCHW input layout.
  static List<List<List<List<double>>>> preprocessImage(img.Image image) {
    final img.Image resized = (image.width == _inputSize && image.height == _inputSize)
        ? image
        : img.copyResize(image, width: _inputSize, height: _inputSize,
            interpolation: img.Interpolation.linear);

    // Build [1, 3, H, W] nested list
    // Outer: batch=1, then C=3, then H rows, then W values
    final List<List<List<double>>> chw = List.generate(
      3,
      (c) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
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
    );

    return [chw]; // wrap in batch dimension
  }

  /// Parses the YOLOv8 output tensor of shape [1, 84, 8400].
  /// Layout per anchor i: rows 0-3 are cx,cy,w,h in 0..640 space;
  /// rows 4..83 are per-class scores (no sigmoid, raw logits on pt models
  /// but YOLOv8 TFLite exports apply sigmoid in the graph — values are
  /// already in [0,1]).
  static List<DetectionResult> parseOutputs(
    List<List<List<double>>> output, // shape [1, 84, 8400]
    List<String> labels, {
    double confidenceThreshold = 0.25,
    double iouThreshold = 0.45,
    int maxDetections = 10,
  }) {
    final int numClasses = labels.length; // 80
    final batch = output[0]; // shape [84, 8400]

    final List<DetectionResult> candidates = [];

    for (int i = 0; i < _numAnchors; i++) {
      double maxConf = 0.0;
      int classId = -1;

      for (int j = 0; j < numClasses; j++) {
        final double conf = batch[4 + j][i];
        if (conf > maxConf) {
          maxConf = conf;
          classId = j;
        }
      }

      if (maxConf > confidenceThreshold && classId >= 0 && classId < numClasses) {
        final double cx = (batch[0][i] / _inputSize.toDouble()).clamp(0.0, 1.0);
        final double cy = (batch[1][i] / _inputSize.toDouble()).clamp(0.0, 1.0);
        final double w  = (batch[2][i] / _inputSize.toDouble()).clamp(0.0, 1.0);
        final double h  = (batch[3][i] / _inputSize.toDouble()).clamp(0.0, 1.0);

        candidates.add(DetectionResult(
          label: labels[classId],
          confidence: maxConf,
          boundingBox: [cx, cy, w, h],
        ));
      }
    }

    // Sort by confidence descending
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Non-Maximum Suppression (class-agnostic for simplicity)
    final List<DetectionResult> nmsResults = [];
    for (final res in candidates) {
      bool keep = true;
      for (final kept in nmsResults) {
        final double iou = _calculateIoU(res.boundingBox, kept.boundingBox);
        if (iou > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) {
        nmsResults.add(res);
      }
      if (nmsResults.length >= maxDetections) break;
    }

    if (nmsResults.isNotEmpty) {
      debugPrint(
        '[YoloDetector] ${nmsResults.length} detection(s): '
        '${nmsResults.take(3).map((d) => "${d.label}(${(d.confidence * 100).toStringAsFixed(0)}%,${d.spatialPosition})").join(", ")}',
      );
    }

    return nmsResults;
  }

  static double _calculateIoU(List<double> box1, List<double> box2) {
    final double b1x1 = box1[0] - box1[2] / 2;
    final double b1y1 = box1[1] - box1[3] / 2;
    final double b1x2 = box1[0] + box1[2] / 2;
    final double b1y2 = box1[1] + box1[3] / 2;

    final double b2x1 = box2[0] - box2[2] / 2;
    final double b2y1 = box2[1] - box2[3] / 2;
    final double b2x2 = box2[0] + box2[2] / 2;
    final double b2y2 = box2[1] + box2[3] / 2;

    final double x1 = b1x1 > b2x1 ? b1x1 : b2x1;
    final double y1 = b1y1 > b2y1 ? b1y1 : b2y1;
    final double x2 = b1x2 < b2x2 ? b1x2 : b2x2;
    final double y2 = b1y2 < b2y2 ? b1y2 : b2y2;

    final double width = x2 - x1;
    final double height = y2 - y1;
    if (width <= 0 || height <= 0) return 0.0;

    final double intersection = width * height;
    final double union = (box1[2] * box1[3]) + (box2[2] * box2[3]) - intersection;
    if (union <= 0) return 0.0;

    return intersection / union;
  }

  /// Runs end-to-end detection on an [img.Image] synchronously on the
  /// main isolate. Frame-skip guard (_isInferring) prevents overlap.
  Future<List<DetectionResult>> detectImage(img.Image image) async {
    if (_interpreter == null || _labels == null || _isInferring) return [];

    _isInferring = true;
    try {
      // Preprocess on a background isolate to avoid UI jank
      final inputTensor = await compute(_preprocessInIsolate, image);

      // Output buffer: nested list matching shape [1, 84, 8400]
      // IsolateInterpreter.copyTo needs a mutable nested List so it can 
      // _duplicateList in-place. We build it once per frame.
      final outputBuffer = List.generate(
        1,
        (_) => List.generate(84, (_) => List<double>.filled(_numAnchors, 0.0)),
      );

      _interpreter!.run(inputTensor, outputBuffer);

      return parseOutputs(outputBuffer, _labels!);
    } catch (e) {
      debugPrint('[YoloDetector] Inference error: $e');
      return [];
    } finally {
      _isInferring = false;
    }
  }

  /// Top-level function for `compute()` — must be a static/top-level fn.
  static List<List<List<List<double>>>> _preprocessInIsolate(img.Image image) {
    return preprocessImage(image);
  }

  /// Runs end-to-end detection on encoded JPEG bytes.
  Future<List<DetectionResult>> detect(Uint8List jpegBytes) async {
    if (_interpreter == null || _labels == null || _isInferring) return [];

    try {
      final img.Image? image = img.decodeImage(jpegBytes);
      if (image == null) {
        debugPrint('[YoloDetector] decodeImage returned null');
        return [];
      }
      return await detectImage(image);
    } catch (e) {
      debugPrint('[YoloDetector] Detection error: $e');
      return [];
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _labels = null;
    _isInferring = false;
  }
}
