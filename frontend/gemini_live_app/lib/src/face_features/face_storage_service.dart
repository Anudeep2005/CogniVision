import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'registered_face.dart';
import 'face_embedding_service.dart';

class FaceStorageService {
  static const String _boxName = 'faces';
  static const double _recognitionThreshold = 0.75;

  final FaceEmbeddingService _embeddingService;
  late Box<RegisteredFace> _box;

  FaceStorageService(this._embeddingService);

  void init() {
    _box = Hive.box<RegisteredFace>(_boxName);
  }

  /// Register a new face with a name
  Future<RegisteredFace> registerFace({
    required String name,
    required List<double> embedding,
  }) async {
    final face = RegisteredFace(
      id: const Uuid().v4(),
      name: name,
      embedding: embedding,
      registeredAt: DateTime.now(),
    );
    await _box.put(face.id, face);
    return face;
  }

  /// Find the best matching face from the database
  RecognitionResult? findMatch(List<double> queryEmbedding) {
    if (_box.isEmpty) return null;

    RegisteredFace? bestMatch;
    double bestScore = -1;

    for (final face in _box.values) {
      final score = _embeddingService.cosineSimilarity(queryEmbedding, face.embedding);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = face;
      }
    }

    if (bestMatch == null || bestScore < _recognitionThreshold) {
      return RecognitionResult(
        face: null,
        confidence: bestScore,
        isMatch: false,
      );
    }

    return RecognitionResult(
      face: bestMatch,
      confidence: bestScore,
      isMatch: true,
    );
  }

  List<RegisteredFace> getAllFaces() => _box.values.toList();

  Future<void> deleteFace(String id) async {
    await _box.delete(id);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}

class RecognitionResult {
  final RegisteredFace? face;
  final double confidence;
  final bool isMatch;

  RecognitionResult({
    required this.face,
    required this.confidence,
    required this.isMatch,
  });
}
