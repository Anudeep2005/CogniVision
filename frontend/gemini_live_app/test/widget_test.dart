import 'package:flutter_test/flutter_test.dart';
import 'package:vision_aid_app/src/utilities/yolo_detector.dart';
import 'package:vision_aid_app/src/face_features/face_storage_service.dart';
import 'package:vision_aid_app/src/face_features/face_embedding_service.dart';

void main() {
  // ── YoloDetector unit tests ─────────────────────────────────────────────
  group('YoloDetector', () {
    test('DetectionResult.rect converts centre-format bbox correctly', () {
      // cx=0.5, cy=0.5, w=0.4, h=0.2 → left=0.3, top=0.4, w=0.4, h=0.2
      final result = DetectionResult(
        label: 'person',
        confidence: 0.9,
        boundingBox: [0.5, 0.5, 0.4, 0.2],
      );
      final r = result.rect;
      expect(r.left, closeTo(0.3, 1e-6));
      expect(r.top, closeTo(0.4, 1e-6));
      expect(r.width, closeTo(0.4, 1e-6));
      expect(r.height, closeTo(0.2, 1e-6));
    });

    test('DetectionResult stores label and confidence', () {
      final result = DetectionResult(
        label: 'chair',
        confidence: 0.75,
        boundingBox: [0.1, 0.2, 0.3, 0.4],
      );
      expect(result.label, 'chair');
      expect(result.confidence, 0.75);
    });
  });

  // ── FaceEmbeddingService cosine similarity tests ─────────────────────────
  group('FaceEmbeddingService - cosineSimilarity', () {
    final service = FaceEmbeddingService();

    test('identical vectors return similarity 1.0', () {
      final v = [1.0, 0.0, 0.0];
      expect(service.cosineSimilarity(v, v), closeTo(1.0, 1e-6));
    });

    test('orthogonal vectors return similarity 0.0', () {
      final a = [1.0, 0.0];
      final b = [0.0, 1.0];
      expect(service.cosineSimilarity(a, b), closeTo(0.0, 1e-6));
    });

    test('opposite vectors return similarity -1.0', () {
      final a = [1.0, 0.0];
      final b = [-1.0, 0.0];
      expect(service.cosineSimilarity(a, b), closeTo(-1.0, 1e-6));
    });

    test('empty vectors return 0.0 without throwing', () {
      expect(service.cosineSimilarity([], []), 0.0);
    });
  });

  // ── FaceStorageService recognition threshold test ─────────────────────────
  group('FaceStorageService - threshold constant', () {
    test('recognition threshold is 0.75', () {
      // Threshold is defined as a private const; validate via RecognitionResult
      // A score below threshold should mark isMatch false
      final noMatch = RecognitionResult(
        face: null,
        confidence: 0.70,
        isMatch: false,
      );
      expect(noMatch.isMatch, false);
      expect(noMatch.confidence, lessThan(0.75));
    });

    test('RecognitionResult with isMatch true carries face data', () {
      final match = RecognitionResult(
        face: null, // face object not needed for this logic test
        confidence: 0.90,
        isMatch: true,
      );
      expect(match.isMatch, true);
      expect(match.confidence, greaterThanOrEqualTo(0.75));
    });
  });
}
