import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'video_input.dart' show RawFrame, YuvFrame;

// ─────────────────────────────────────────────────────────────────────────────
// Tunables
// ─────────────────────────────────────────────────────────────────────────────

const int _kInputSize = 640; // model input is [1, 3, 640, 640] (NCHW, float32)
const int _kNumRows = 84; // 4 box values + 80 class scores
const int _kNumAnchors = 8400;

const double _kConfThreshold = 0.45;
const double _kIouThreshold = 0.45;
const int _kMaxDetections = 10;

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
// Worker isolate (everything heavy happens here, never on the UI isolate)
// ─────────────────────────────────────────────────────────────────────────────

void _yoloIsolateEntry(SendPort callerPort) {
  final port = ReceivePort();
  callerPort.send(port.sendPort);

  final worker = _YoloWorker();

  port.listen((dynamic msg) {
    if (msg is! Map) return;
    final String type = msg['type'] as String;
    final SendPort? reply = msg['replyPort'] as SendPort?;

    try {
      switch (type) {
        case 'init':
          final String? error = worker.init(
            msg['modelBytes'] as Uint8List,
            (msg['labels'] as List<dynamic>).cast<String>(),
            msg['threads'] as int,
          );
          reply?.send(error == null ? true : 'init_error:$error');
          break;
        case 'yuv':
          reply?.send(worker.runYuv(msg));
          break;
        case 'rgb':
          reply?.send(worker.runRgb(msg));
          break;
        case 'shutdown':
          worker.close();
          port.close();
          break;
      }
    } catch (e) {
      reply?.send(<String, dynamic>{'error': e.toString()});
    }
  });
}

class _YoloWorker {
  Interpreter? _interpreter;
  List<String> _labels = const [];

  /// true  → raw-bytes I/O (no nested lists, fastest)
  /// false → nested-list fallback (slow, only if the fast path is unsupported)
  bool _fastIo = true;

  // Re-used buffers (allocated once, never per frame).
  final Float32List _input = Float32List(3 * _kInputSize * _kInputSize);
  late final Uint8List _inputBytes = _input.buffer.asUint8List();
  final Uint8List _outBytes = Uint8List(_kNumRows * _kNumAnchors * 4);
  late final Float32List _out = _outBytes.buffer.asFloat32List();
  final Float32List _best = Float32List(_kNumAnchors);
  final Int32List _cls = Int32List(_kNumAnchors);
  final Float32List _lut = Float32List(256);

  // Sampling tables (rebuilt only when the frame geometry changes).
  final Int32List _colTab = Int32List(_kInputSize);
  final Int32List _rowTab = Int32List(_kInputSize);
  int _tabW = -1;
  int _tabH = -1;
  int _tabRot = -1;

  _YoloWorker() {
    for (int i = 0; i < 256; i++) {
      _lut[i] = i / 255.0;
    }
  }

  // ── init ──────────────────────────────────────────────────────────────────

  /// Returns null on success or an error message.
  String? init(Uint8List modelBytes, List<String> labels, int threads) {
    try {
      _labels = labels;
      final options = InterpreterOptions()..threads = threads;
      final interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      _interpreter = interpreter;

      final inShape = interpreter.getInputTensor(0).shape;
      final outShape = interpreter.getOutputTensor(0).shape;
      if (inShape.length != 4 ||
          inShape[1] != 3 ||
          inShape[2] != _kInputSize ||
          inShape[3] != _kInputSize) {
        return 'Unexpected input shape $inShape (expected [1, 3, 640, 640]).';
      }
      if (outShape.length != 3 ||
          outShape[1] != _kNumRows ||
          outShape[2] != _kNumAnchors) {
        return 'Unexpected output shape $outShape (expected [1, 84, 8400]). '
            'If you switched models (e.g. YOLO26) the parser must be updated.';
      }

      // Self-test: pick the fastest I/O path that actually works here.
      // The output buffer is pre-filled with 0xFF (= NaN floats), so any value
      // the model really wrote is detectable, whatever its magnitude.
      _input.fillRange(0, _input.length, 0.0);
      _fastIo = true;
      bool ok = false;
      try {
        _outBytes.fillRange(0, _outBytes.length, 0xFF);
        interpreter.run(_inputBytes, _outBytes);
        ok = _outputWasWritten();
      } catch (_) {
        ok = false;
      }
      if (!ok) {
        _fastIo = false;
        _outBytes.fillRange(0, _outBytes.length, 0xFF);
        _runCompat();
        if (!_outputWasWritten()) {
          return 'Model produced no output during self-test.';
        }
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  bool _outputWasWritten() {
    // Sample the box rows and a few class rows; NaN means "never written".
    for (int r = 0; r < 8; r++) {
      final int base = r * _kNumAnchors;
      for (int i = 0; i < 64; i++) {
        if (!_out[base + i].isNaN) return true;
      }
    }
    return false;
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }

  // ── entry points ──────────────────────────────────────────────────────────

  Map<String, dynamic> runYuv(Map msg) {
    final sw = Stopwatch()..start();

    final Uint8List y =
        (msg['y'] as TransferableTypedData).materialize().asUint8List();
    final Uint8List u =
        (msg['u'] as TransferableTypedData).materialize().asUint8List();
    final Uint8List v =
        (msg['v'] as TransferableTypedData).materialize().asUint8List();

    _fillFromYuv(
      y,
      u,
      v,
      msg['width'] as int,
      msg['height'] as int,
      msg['yRowStride'] as int,
      msg['uRowStride'] as int,
      msg['vRowStride'] as int,
      msg['uPixelStride'] as int,
      msg['vPixelStride'] as int,
      msg['rotation'] as int,
    );
    return _inferAndParse(sw);
  }

  Map<String, dynamic> runRgb(Map msg) {
    final sw = Stopwatch()..start();
    final Uint8List rgb =
        (msg['rgb'] as TransferableTypedData).materialize().asUint8List();
    _fillFromRgb(rgb, msg['width'] as int, msg['height'] as int);
    return _inferAndParse(sw);
  }

  Map<String, dynamic> _inferAndParse(Stopwatch sw) {
    final int preMs = sw.elapsedMilliseconds;
    sw.reset();

    if (_fastIo) {
      _interpreter!.run(_inputBytes, _outBytes);
    } else {
      _runCompat();
    }
    final int infMs = sw.elapsedMilliseconds;
    sw.reset();

    final detections = _parseFlat();
    return <String, dynamic>{
      'det': detections,
      'preMs': preMs,
      'infMs': infMs,
      'postMs': sw.elapsedMilliseconds,
    };
  }

  /// Slow fallback using nested lists (only used if the raw-bytes path fails).
  void _runCompat() {
    final nestedIn = _input.reshape([1, 3, _kInputSize, _kInputSize]);
    final nestedOut = <List<List<double>>>[
      List.generate(_kNumRows, (_) => List<double>.filled(_kNumAnchors, 0.0)),
    ];
    _interpreter!.run(nestedIn, nestedOut);
    final rows = nestedOut[0];
    int k = 0;
    for (int r = 0; r < _kNumRows; r++) {
      final row = rows[r];
      for (int i = 0; i < _kNumAnchors; i++) {
        _out[k++] = row[i];
      }
    }
  }

  // ── preprocessing: YUV (sensor orientation) → NCHW float tensor ───────────
  //
  // One pass does: YUV→RGB, rotate upright, stretch to 640×640, /255.
  // (Verified against a numpy reference for 0/90/180/270.)

  void _ensureYuvTables(int w, int h, int rot) {
    if (w == _tabW && h == _tabH && rot == _tabRot) return;
    final bool transposed = rot == 90 || rot == 270;
    final int ow = transposed ? h : w;
    final int oh = transposed ? w : h;

    for (int t = 0; t < _kInputSize; t++) {
      final int ox = (t * ow) ~/ _kInputSize;
      final int oy = (t * oh) ~/ _kInputSize;
      if (!transposed) {
        _colTab[t] = rot == 0 ? ox : w - 1 - ox; // source x
        _rowTab[t] = rot == 0 ? oy : h - 1 - oy; // source y
      } else {
        _colTab[t] = rot == 90 ? h - 1 - ox : ox; // source y
        _rowTab[t] = rot == 90 ? oy : w - 1 - oy; // source x
      }
    }
    _tabW = w;
    _tabH = h;
    _tabRot = rot;
  }

  void _fillFromYuv(
    Uint8List yb,
    Uint8List ub,
    Uint8List vb,
    int w,
    int h,
    int ys,
    int us,
    int vs,
    int up,
    int vp,
    int rotation,
  ) {
    final int rot = ((((rotation % 360) + 360) % 360) ~/ 90) * 90;
    _ensureYuvTables(w, h, rot);
    final bool transposed = rot == 90 || rot == 270;

    const int size = _kInputSize;
    const int plane = size * size;
    final Float32List tensor = _input;
    final Float32List lut = _lut;
    final Int32List col = _colTab;
    final Int32List row = _rowTab;

    for (int ty = 0; ty < size; ty++) {
      final int r = row[ty];
      final int base = ty * size;
      for (int tx = 0; tx < size; tx++) {
        final int c = col[tx];
        final int x = transposed ? r : c;
        final int y = transposed ? c : r;

        final int yv = yb[y * ys + x];
        final int uvRow = y >> 1;
        final int uvCol = x >> 1;
        final int uv = ub[uvRow * us + uvCol * up] - 128;
        final int vv = vb[uvRow * vs + uvCol * vp] - 128;

        int rr = yv + ((1436 * vv) >> 10);
        int gg = yv - ((352 * uv + 731 * vv) >> 10);
        int bb = yv + ((1815 * uv) >> 10);
        rr = rr < 0 ? 0 : (rr > 255 ? 255 : rr);
        gg = gg < 0 ? 0 : (gg > 255 ? 255 : gg);
        bb = bb < 0 ? 0 : (bb > 255 ? 255 : bb);

        final int i = base + tx;
        tensor[i] = lut[rr];
        tensor[plane + i] = lut[gg];
        tensor[2 * plane + i] = lut[bb];
      }
    }
  }

  /// Generic packed-RGB (already upright) → tensor, nearest-neighbour stretch.
  void _fillFromRgb(Uint8List rgb, int sw, int sh) {
    const int size = _kInputSize;
    const int plane = size * size;
    final Float32List tensor = _input;
    final Float32List lut = _lut;

    final cols = Int32List(size);
    for (int t = 0; t < size; t++) {
      cols[t] = ((t * sw) ~/ size) * 3;
    }
    for (int ty = 0; ty < size; ty++) {
      final int rowOff = ((ty * sh) ~/ size) * sw * 3;
      final int base = ty * size;
      for (int tx = 0; tx < size; tx++) {
        final int p = rowOff + cols[tx];
        final int i = base + tx;
        tensor[i] = lut[rgb[p]];
        tensor[plane + i] = lut[rgb[p + 1]];
        tensor[2 * plane + i] = lut[rgb[p + 2]];
      }
    }
  }

  // ── postprocessing on the flat [84 * 8400] output ─────────────────────────
  //
  // Layout is row-major: value(row r, anchor i) = out[r * 8400 + i].
  // Rows 0..3 = cx, cy, w, h (ALREADY normalised 0..1 for this TFLite export),
  // rows 4..83 = class scores. Class-major scan keeps memory access sequential.

  List<Map<String, dynamic>> _parseFlat() {
    const int n = _kNumAnchors;
    final Float32List o = _out;
    final int numClasses = math.min(_labels.length, _kNumRows - 4);

    _best.fillRange(0, n, 0.0);
    _cls.fillRange(0, n, -1);

    for (int j = 0; j < numClasses; j++) {
      final int base = (4 + j) * n;
      for (int i = 0; i < n; i++) {
        final double c = o[base + i];
        if (c > _best[i]) {
          _best[i] = c;
          _cls[i] = j;
        }
      }
    }

    final candidates = <int>[];
    for (int i = 0; i < n; i++) {
      if (_best[i] > _kConfThreshold && _cls[i] >= 0) candidates.add(i);
    }
    candidates.sort((a, b) => _best[b].compareTo(_best[a]));

    final kept = <int>[];
    for (final int i in candidates) {
      bool keep = true;
      for (final int k in kept) {
        if (_iou(o, i, k) > _kIouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) kept.add(i);
      if (kept.length >= _kMaxDetections) break;
    }

    return kept
        .map<Map<String, dynamic>>((int i) => <String, dynamic>{
              'label': _labels[_cls[i]],
              'confidence': _best[i].toDouble(),
              'cx': o[i].clamp(0.0, 1.0).toDouble(),
              'cy': o[n + i].clamp(0.0, 1.0).toDouble(),
              'w': o[2 * n + i].clamp(0.0, 1.0).toDouble(),
              'h': o[3 * n + i].clamp(0.0, 1.0).toDouble(),
            })
        .toList();
  }

  static double _iou(Float32List o, int a, int b) {
    const int n = _kNumAnchors;
    final double acx = o[a],
        acy = o[n + a],
        aw = o[2 * n + a],
        ah = o[3 * n + a];
    final double bcx = o[b],
        bcy = o[n + b],
        bw = o[2 * n + b],
        bh = o[3 * n + b];

    final double ix1 = math.max(acx - aw / 2, bcx - bw / 2);
    final double iy1 = math.max(acy - ah / 2, bcy - bh / 2);
    final double ix2 = math.min(acx + aw / 2, bcx + bw / 2);
    final double iy2 = math.min(acy + ah / 2, bcy + bh / 2);

    final double iw = ix2 - ix1;
    final double ih = iy2 - iy1;
    if (iw <= 0 || ih <= 0) return 0.0;

    final double inter = iw * ih;
    final double union = aw * ah + bw * bh - inter;
    return union <= 0 ? 0.0 : inter / union;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YoloDetector — public API (UI isolate side)
// ─────────────────────────────────────────────────────────────────────────────

class YoloDetector {
  Isolate? _isolate;
  SendPort? _workerPort;
  bool _isolateReady = false;
  bool _isInferring = false;
  Future<void>? _initFuture;

  List<String>? _labels;

  int _lastPreMs = 0;
  int _lastInfMs = 0;
  int _lastPostMs = 0;
  int _frameCount = 0;

  bool get isInferring => _isInferring;
  bool get isInitialized => _isolateReady && _labels != null;

  /// Exposed for tests only.
  List<String>? get labels => _labels;

  /// Timings of the last processed frame (milliseconds, measured in the worker).
  int get lastPreprocessMs => _lastPreMs;
  int get lastInferenceMs => _lastInfMs;
  int get lastPostprocessMs => _lastPostMs;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Idempotent and safe to call concurrently (a second call joins the first).
  Future<void> init() {
    if (isInitialized) return Future<void>.value();
    return _initFuture ??= _init().whenComplete(() => _initFuture = null);
  }

  Future<void> _init() async {
    try {
      final byteData = await rootBundle.load('assets/models/yolov8n.tflite');
      final Uint8List modelBytes = byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

      final labelsRaw =
          await rootBundle.loadString('assets/models/yolov8n.txt');
      // trim(): the label file uses Windows line endings (\r\n).
      final labels = labelsRaw
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final receivePort = ReceivePort();
      _isolate = await Isolate.spawn(
        _yoloIsolateEntry,
        receivePort.sendPort,
        debugName: 'YoloInferenceWorker',
      );
      _workerPort = await receivePort.first as SendPort;
      receivePort.close();

      final int threads =
          math.max(2, math.min(4, Platform.numberOfProcessors ~/ 2));

      final initReply = ReceivePort();
      _workerPort!.send(<String, dynamic>{
        'type': 'init',
        'modelBytes': modelBytes,
        'labels': labels,
        'threads': threads,
        'replyPort': initReply.sendPort,
      });
      final dynamic initResult = await initReply.first;
      initReply.close();

      if (initResult == true) {
        _labels = labels;
        _isolateReady = true;
        debugPrint('[YoloDetector] Worker ready — ${labels.length} classes, '
            '$threads threads');
      } else {
        throw Exception('[YoloDetector] Worker init failed: $initResult');
      }
    } catch (e) {
      debugPrint('[YoloDetector] Initialization error: $e');
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _workerPort = null;
      _isolateReady = false;
      _labels = null;
      rethrow;
    }
  }

  void dispose() {
    _workerPort?.send(<String, dynamic>{'type': 'shutdown'});
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _workerPort = null;
    _isolateReady = false;
    _isInferring = false;
    _labels = null;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Preferred path: takes the raw camera frame (sensor orientation) and does
  /// convert + rotate + resize + normalise + inference + decode in the worker.
  ///
  /// Returns `null` when the frame was skipped (worker busy / not ready) or
  /// failed, and a (possibly empty) list when inference really ran. Callers
  /// should keep showing the previous boxes on `null`.
  Future<List<DetectionResult>?> detectYuv(YuvFrame frame) async {
    if (!_isolateReady || _workerPort == null || _isInferring) return null;
    _isInferring = true;
    try {
      return await _request(<String, dynamic>{
        'type': 'yuv',
        'y': TransferableTypedData.fromList(<TypedData>[frame.y]),
        'u': TransferableTypedData.fromList(<TypedData>[frame.u]),
        'v': TransferableTypedData.fromList(<TypedData>[frame.v]),
        'width': frame.width,
        'height': frame.height,
        'yRowStride': frame.yRowStride,
        'uRowStride': frame.uRowStride,
        'vRowStride': frame.vRowStride,
        'uPixelStride': frame.uPixelStride,
        'vPixelStride': frame.vPixelStride,
        'rotation': frame.rotation,
      });
    } finally {
      _isInferring = false;
    }
  }

  /// Already-upright packed RGB frame (e.g. from `yuvToUprightRgb`).
  Future<List<DetectionResult>?> detectRaw(RawFrame frame) async {
    if (!_isolateReady || _workerPort == null || _isInferring) return null;
    _isInferring = true;
    try {
      return await _request(<String, dynamic>{
        'type': 'rgb',
        'rgb': TransferableTypedData.fromList(<TypedData>[frame.rgbBytes]),
        'width': frame.width,
        'height': frame.height,
      });
    } finally {
      _isInferring = false;
    }
  }

  Future<List<DetectionResult>?> _request(Map<String, dynamic> message) async {
    final reply = ReceivePort();
    message['replyPort'] = reply.sendPort;
    try {
      _workerPort!.send(message);
      final dynamic raw = await reply.first.timeout(const Duration(seconds: 8));

      if (raw is! Map) return null;
      if (raw['error'] != null) {
        debugPrint('[YoloDetector] Worker error: ${raw['error']}');
        return null;
      }

      _lastPreMs = (raw['preMs'] as num).toInt();
      _lastInfMs = (raw['infMs'] as num).toInt();
      _lastPostMs = (raw['postMs'] as num).toInt();
      _frameCount++;
      if (kDebugMode && _frameCount % 20 == 0) {
        debugPrint('[YoloDetector] pre=${_lastPreMs}ms '
            'inference=${_lastInfMs}ms post=${_lastPostMs}ms');
      }

      final List<dynamic> list = raw['det'] as List<dynamic>;
      return list.map<DetectionResult>((dynamic item) {
        final Map m = item as Map;
        return DetectionResult(
          label: m['label'] as String,
          confidence: (m['confidence'] as num).toDouble(),
          boundingBox: <double>[
            (m['cx'] as num).toDouble(),
            (m['cy'] as num).toDouble(),
            (m['w'] as num).toDouble(),
            (m['h'] as num).toDouble(),
          ],
        );
      }).toList();
    } on TimeoutException {
      debugPrint('[YoloDetector] Inference timed out');
      return null;
    } catch (e) {
      debugPrint('[YoloDetector] Inference error: $e');
      return null;
    } finally {
      reply.close();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Static helpers — kept for unit tests
  // ─────────────────────────────────────────────────────────────────────────

  /// Converts an [img.Image] to a nested NCHW [1, 3, 640, 640] float list.
  /// (Slow; only meant for tests. The live path uses the flat worker pipeline.)
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

  /// Decodes a nested model output [1, 84, 8400] and applies NMS.
  ///
  /// [normalizedCoords] must be true for the bundled TFLite model, whose
  /// box rows are already 0..1. Pass false for a model that emits pixels (0..640).
  static List<DetectionResult> parseOutputs(
    List<List<List<double>>> output,
    List<String> labels, {
    double confidenceThreshold = _kConfThreshold,
    double iouThreshold = _kIouThreshold,
    int maxDetections = _kMaxDetections,
    bool normalizedCoords = true,
  }) {
    final int numClasses = labels.length;
    final batch = output[0];
    final double scale = normalizedCoords ? 1.0 : _kInputSize.toDouble();

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

      if (maxConf > confidenceThreshold &&
          classId >= 0 &&
          classId < numClasses) {
        candidates.add(DetectionResult(
          label: labels[classId],
          confidence: maxConf,
          boundingBox: [
            (batch[0][i] / scale).clamp(0.0, 1.0),
            (batch[1][i] / scale).clamp(0.0, 1.0),
            (batch[2][i] / scale).clamp(0.0, 1.0),
            (batch[3][i] / scale).clamp(0.0, 1.0),
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
    final union = box1[2] * box1[3] + box2[2] * box2[3] - intersection;
    return union <= 0 ? 0.0 : intersection / union;
  }
}
