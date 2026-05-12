import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Real face embedding service using MobileFaceNet TFLite model.
///
/// The model accepts a [1, 112, 112, 3] float32 tensor (pixels normalised to
/// [-1, 1]) and outputs a [1, 192] float32 embedding vector.
/// Cosine similarity ≥ 0.75 → same person.
class FaceEmbeddingService {
  static const String _modelFilename = 'mobile_face_net.tflite';
  static const String _modelUrl =
      'https://github.com/ngtrphuong/facerecognition/raw/main/assets/mobilefacenet.tflite';

  static const int _inputSize   = 112;
  static const int _embeddingSize = 192;

  Interpreter? _interpreter;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call once at app start.  Downloads the model if not already cached.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final modelFile = await _getOrDownloadModel();
      _interpreter = Interpreter.fromFile(modelFile);
      _isInitialized = true;
      debugPrint('[FaceEmbedding] MobileFaceNet loaded ✔');
    } catch (e) {
      _isInitialized = false;
      debugPrint('[FaceEmbedding] Failed to load model: $e');
    }
  }

  /// Extract a 192-d normalised embedding from a cropped face [img.Image].
  /// Returns null if the model is not loaded.
  Future<List<double>?> getEmbedding(img.Image faceImage) async {
    if (!_isInitialized || _interpreter == null) return null;

    final resized = img.copyResize(
      faceImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Build [1, 112, 112, 3] float32 input tensor
    final input = _buildInputTensor(resized);

    // Output buffer [1, 192]
    final outputBuffer = [List<double>.filled(_embeddingSize, 0.0)];

    _interpreter!.run(input, outputBuffer);

    return _normalize(outputBuffer[0]);
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot   += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Returns cached model file; downloads it first time.
  Future<File> _getOrDownloadModel() async {
    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_modelFilename');
    if (await file.exists()) return file;

    debugPrint('[FaceEmbedding] Downloading MobileFaceNet model...');
    final response = await http.get(Uri.parse(_modelUrl));
    if (response.statusCode != 200) {
      throw Exception('Model download failed: HTTP ${response.statusCode}');
    }
    await file.writeAsBytes(response.bodyBytes);
    debugPrint('[FaceEmbedding] Model saved to ${file.path}');
    return file;
  }

  /// Converts img.Image to [1, H, W, 3] float32 list normalised to [-1, 1].
  List<List<List<List<double>>>> _buildInputTensor(img.Image image) {
    return List.generate(1, (_) =>
      List.generate(_inputSize, (y) =>
        List.generate(_inputSize, (x) {
          final pixel = image.getPixel(x, y);
          return [
            (pixel.r / 127.5) - 1.0,
            (pixel.g / 127.5) - 1.0,
            (pixel.b / 127.5) - 1.0,
          ];
        }),
      ),
    );
  }

  List<double> _normalize(List<double> v) {
    final norm = sqrt(v.fold(0.0, (s, e) => s + e * e));
    if (norm == 0) return v;
    return v.map((e) => e / norm).toList();
  }
}
