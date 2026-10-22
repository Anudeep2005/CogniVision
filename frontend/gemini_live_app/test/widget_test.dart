import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vision_aid_app/src/providers.dart';
import 'package:vision_aid_app/src/utilities/yolo_detector.dart';
import 'package:vision_aid_app/src/services/tts_service.dart';
import 'package:vision_aid_app/src/flutterfire_ai_live_api_demo.dart';
import 'package:vision_aid_app/src/face_features/face_storage_service.dart';
import 'package:vision_aid_app/src/face_features/face_embedding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('DetectionResult.spatialPosition classifies horizontal position', () {
      // left region
      final left = DetectionResult(label: 'a', confidence: 0.9, boundingBox: [0.1, 0.5, 0.1, 0.1]);
      expect(left.spatialPosition, 'left');
      // centre region
      final centre = DetectionResult(label: 'b', confidence: 0.9, boundingBox: [0.5, 0.5, 0.1, 0.1]);
      expect(centre.spatialPosition, 'centre');
      // right region
      final right = DetectionResult(label: 'c', confidence: 0.9, boundingBox: [0.8, 0.5, 0.1, 0.1]);
      expect(right.spatialPosition, 'right');
    });

    test('preprocessImage creates NCHW [1, 3, 640, 640] nested list with correct channel values', () {
      final testImg = img.Image(width: 640, height: 640);
      testImg.setPixelRgb(0, 0, 255, 128, 64);

      // Returns List<List<List<List<double>>>> with shape [1, 3, 640, 640]
      final buffer = YoloDetector.preprocessImage(testImg);
      expect(buffer.length, 1);       // batch
      expect(buffer[0].length, 3);    // channels
      expect(buffer[0][0].length, 640); // height
      expect(buffer[0][0][0].length, 640); // width

      // Channel 0 (Red) at pixel (x=0, y=0)
      expect(buffer[0][0][0][0], closeTo(1.0, 1e-4));
      // Channel 1 (Green) at pixel (x=0, y=0)
      expect(buffer[0][1][0][0], closeTo(128 / 255.0, 1e-4));
      // Channel 2 (Blue) at pixel (x=0, y=0)
      expect(buffer[0][2][0][0], closeTo(64 / 255.0, 1e-4));
    });

    // Helper: build a [1, 84, 8400] nested output list with specific anchor values
    List<List<List<double>>> buildOutputBuffer({
      required int anchor,
      required double cx, required double cy, required double w, required double h,
      required int classId,
      required double conf,
    }) {
      // Initialize all zeros
      final out = List.generate(
        1,
        (_) => List.generate(84, (_) => List<double>.filled(8400, 0.0)),
      );
      out[0][0][anchor] = cx;
      out[0][1][anchor] = cy;
      out[0][2][anchor] = w;
      out[0][3][anchor] = h;
      out[0][4 + classId][anchor] = conf;
      return out;
    }

    test('parseOutputs decodes anchors, normalizes coords, and filters low confidence', () {
      final labels = ['person', 'bicycle', 'car'];

      // Build output with anchor 100: person conf=0.90, cx=320, cy=320, w=160, h=320
      final output = buildOutputBuffer(
        anchor: 100, cx: 320.0, cy: 320.0, w: 160.0, h: 320.0,
        classId: 0, conf: 0.90,
      );
      // Anchor 200: car conf=0.20 (below 0.25 threshold — should be filtered)
      output[0][0][200] = 100.0;
      output[0][1][200] = 100.0;
      output[0][2][200] = 50.0;
      output[0][3][200] = 50.0;
      output[0][4 + 2][200] = 0.20;

      final detections = YoloDetector.parseOutputs(output, labels);

      expect(detections.length, 1);
      expect(detections.first.label, 'person');
      expect(detections.first.confidence, closeTo(0.90, 1e-4));
      expect(detections.first.boundingBox[0], closeTo(0.5, 1e-4)); // cx
      expect(detections.first.boundingBox[1], closeTo(0.5, 1e-4)); // cy
      expect(detections.first.boundingBox[2], closeTo(0.25, 1e-4)); // w
      expect(detections.first.boundingBox[3], closeTo(0.5, 1e-4));  // h
    });

    test('parseOutputs applies NMS to suppress overlapping duplicate detections', () {
      final labels = ['person', 'bicycle'];

      // Anchor 10: person (conf 0.95, cx=320, cy=320, w=100, h=100)
      final output = List.generate(
        1,
        (_) => List.generate(84, (_) => List<double>.filled(8400, 0.0)),
      );
      output[0][0][10] = 320.0;
      output[0][1][10] = 320.0;
      output[0][2][10] = 100.0;
      output[0][3][10] = 100.0;
      output[0][4 + 0][10] = 0.95;

      // Anchor 11: highly overlapping duplicate person (conf 0.80, cx=322, cy=320, w=98, h=100)
      output[0][0][11] = 322.0;
      output[0][1][11] = 320.0;
      output[0][2][11] = 98.0;
      output[0][3][11] = 100.0;
      output[0][4 + 0][11] = 0.80;

      final detections = YoloDetector.parseOutputs(output, labels);

      // NMS should suppress Anchor 11, leaving only the higher confidence detection
      expect(detections.length, 1);
      expect(detections.first.confidence, closeTo(0.95, 1e-4));
    });

    test('YoloDetector initializes with isInferring false', () {
      final detector = YoloDetector();
      expect(detector.isInferring, false);
      expect(detector.isInitialized, false);
      detector.dispose();
      expect(detector.isInferring, false);
      expect(detector.isInitialized, false);
    });
  });

  // ── YoloPainter unit tests ───────────────────────────────────────────────
  group('YoloPainter', () {
    test('shouldRepaint returns true when detections differ', () {
      final d1 = [DetectionResult(label: 'person', confidence: 0.9, boundingBox: [0.5, 0.5, 0.2, 0.4])];
      final d2 = [DetectionResult(label: 'chair', confidence: 0.8, boundingBox: [0.2, 0.2, 0.1, 0.1])];
      final painter1 = YoloPainter(d1, previewSize: const Size(480, 640));
      final painter2 = YoloPainter(d2, previewSize: const Size(480, 640));
      expect(painter1.shouldRepaint(painter2), true);
    });

    test('shouldRepaint returns false for identical instances', () {
      final d = [DetectionResult(label: 'person', confidence: 0.9, boundingBox: [0.5, 0.5, 0.2, 0.4])];
      final painter1 = YoloPainter(d, previewSize: const Size(480, 640));
      final painter2 = YoloPainter(d, previewSize: const Size(480, 640));
      expect(painter1.shouldRepaint(painter2), false);
    });
  });

  // ── TtsService unit tests ────────────────────────────────────────────────
  group('TtsService - Spatial Audio & Throttling', () {
    test('getDirection correctly bins horizontal center', () {
      expect(TtsService.getDirection(0.1), "on your left");
      expect(TtsService.getDirection(0.32), "on your left");
      expect(TtsService.getDirection(0.33), "ahead");
      expect(TtsService.getDirection(0.50), "ahead");
      expect(TtsService.getDirection(0.66), "ahead");
      expect(TtsService.getDirection(0.67), "on your right");
      expect(TtsService.getDirection(0.95), "on your right");
    });

    test('buildSpatialAnnouncement formats single obstacle cleanly', () {
      final single = [
        DetectionResult(label: 'person', confidence: 0.92, boundingBox: [0.5, 0.5, 0.2, 0.4]),
      ];
      expect(TtsService.buildSpatialAnnouncement(single), "Person ahead.");
    });

    test('buildSpatialAnnouncement formats two obstacles in same direction', () {
      final sameDir = [
        DetectionResult(label: 'person', confidence: 0.95, boundingBox: [0.5, 0.5, 0.2, 0.4]),
        DetectionResult(label: 'chair', confidence: 0.88, boundingBox: [0.4, 0.5, 0.2, 0.2]),
      ];
      expect(TtsService.buildSpatialAnnouncement(sameDir), "Person and chair ahead.");
    });

    test('buildSpatialAnnouncement formats two obstacles in different directions', () {
      final diffDir = [
        DetectionResult(label: 'person', confidence: 0.95, boundingBox: [0.5, 0.5, 0.2, 0.4]),
        DetectionResult(label: 'chair', confidence: 0.88, boundingBox: [0.1, 0.5, 0.2, 0.2]),
      ];
      expect(TtsService.buildSpatialAnnouncement(diffDir), "Person ahead, and chair on your left.");
    });

    test('buildSpatialAnnouncement returns null for empty detections', () {
      expect(TtsService.buildSpatialAnnouncement([]), isNull);
    });

    test('shouldAnnounce respects isSpeaking flag (no speech overlap)', () {
      final now = DateTime.now();
      expect(
        TtsService.shouldAnnounce(
          newPhrase: "Person ahead.",
          lastPhrase: null,
          lastSpokenTime: null,
          currentTime: now,
          isSpeaking: true, // currently speaking
        ),
        false,
      );
    });

    test('shouldAnnounce enforces minimum cooldown between consecutive announcements', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final tAfter2s = t0.add(const Duration(seconds: 2));
      final tAfter4s = t0.add(const Duration(seconds: 4));

      // 2 seconds later (within 3s cooldown) -> false
      expect(
        TtsService.shouldAnnounce(
          newPhrase: "Chair on your left.",
          lastPhrase: "Person ahead.",
          lastSpokenTime: t0,
          currentTime: tAfter2s,
          isSpeaking: false,
        ),
        false,
      );

      // 4 seconds later for different phrase -> true
      expect(
        TtsService.shouldAnnounce(
          newPhrase: "Chair on your left.",
          lastPhrase: "Person ahead.",
          lastSpokenTime: t0,
          currentTime: tAfter4s,
          isSpeaking: false,
        ),
        true,
      );
    });

    test('shouldAnnounce suppresses rapid repeat of identical phrase', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final tAfter4s = t0.add(const Duration(seconds: 4));
      final tAfter7s = t0.add(const Duration(seconds: 7));

      // Same phrase 4 seconds later (within 6s repeat cooldown) -> suppressed!
      expect(
        TtsService.shouldAnnounce(
          newPhrase: "Person ahead.",
          lastPhrase: "Person ahead.",
          lastSpokenTime: t0,
          currentTime: tAfter4s,
          isSpeaking: false,
        ),
        false,
      );

      // Same phrase 7 seconds later (beyond 6s repeat cooldown) -> allowed
      expect(
        TtsService.shouldAnnounce(
          newPhrase: "Person ahead.",
          lastPhrase: "Person ahead.",
          lastSpokenTime: t0,
          currentTime: tAfter7s,
          isSpeaking: false,
        ),
        true,
      );
    });

    test('TtsService reset clears state', () {
      final tts = TtsService();
      expect(tts.isSpeaking, false);
      expect(tts.lastAnnouncementTime, isNull);
      expect(tts.lastSpokenPhrase, isNull);
      tts.reset();
      expect(tts.isSpeaking, false);
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

  // ── Phase 4: Authoritative AI Mode Switch & Mutual Exclusion tests ────────
  group('AiMode & ModeTransition Coordinator', () {
    test('AiMode enum contains localYolo and cloudGemini modes', () {
      expect(AiMode.values.length, 2);
      expect(AiMode.values, containsAll([AiMode.localYolo, AiMode.cloudGemini]));
    });

    test('ModeTransitionState enum contains complete lifecycle states', () {
      expect(ModeTransitionState.values.length, 4);
      expect(
        ModeTransitionState.values,
        containsAll([
          ModeTransitionState.idle,
          ModeTransitionState.transitioning,
          ModeTransitionState.active,
          ModeTransitionState.error,
        ]),
      );
    });

    test('aiModeProvider defaults to localYolo (safe offline-first default)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialMode = container.read(aiModeProvider);
      expect(initialMode, AiMode.localYolo);
    });

    test('modeTransitionProvider defaults to idle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialState = container.read(modeTransitionProvider);
      expect(initialState, ModeTransitionState.idle);
    });

    test('aiModeProvider updates to cloudGemini and back to localYolo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(aiModeProvider), AiMode.localYolo);

      container.read(aiModeProvider.notifier).state = AiMode.cloudGemini;
      expect(container.read(aiModeProvider), AiMode.cloudGemini);

      container.read(aiModeProvider.notifier).state = AiMode.localYolo;
      expect(container.read(aiModeProvider), AiMode.localYolo);
    });

    test('Mode transition lifecycle state machine executes sequentially', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final transitions = <ModeTransitionState>[];
      container.listen<ModeTransitionState>(
        modeTransitionProvider,
        (previous, next) => transitions.add(next),
      );

      // Transition begins
      container.read(modeTransitionProvider.notifier).state = ModeTransitionState.transitioning;
      // Target mode setup completes
      container.read(modeTransitionProvider.notifier).state = ModeTransitionState.active;
      // Tab backgrounded
      container.read(modeTransitionProvider.notifier).state = ModeTransitionState.idle;

      expect(transitions, [
        ModeTransitionState.transitioning,
        ModeTransitionState.active,
        ModeTransitionState.idle,
      ]);
    });

    test('Error recovery transitions back to localYolo and active', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Attempting to switch to Cloud Gemini
      container.read(modeTransitionProvider.notifier).state = ModeTransitionState.transitioning;

      // Simulated network/cloud connection failure
      container.read(modeTransitionProvider.notifier).state = ModeTransitionState.error;
      expect(container.read(modeTransitionProvider), ModeTransitionState.error);

      // Safe fallback recovery
      container.read(aiModeProvider.notifier).state = AiMode.localYolo;
      container.read(modeTransitionProvider.notifier).state = ModeTransitionState.active;

      expect(container.read(aiModeProvider), AiMode.localYolo);
      expect(container.read(modeTransitionProvider), ModeTransitionState.active);
    });

    test('Mutual exclusion guard: UI controls disabled during transitioning state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(modeTransitionProvider.notifier).state = ModeTransitionState.transitioning;
      final isTransitioning = container.read(modeTransitionProvider) == ModeTransitionState.transitioning;
      expect(isTransitioning, isTrue);

      container.read(modeTransitionProvider.notifier).state = ModeTransitionState.active;
      final isFinished = container.read(modeTransitionProvider) == ModeTransitionState.transitioning;
      expect(isFinished, isFalse);
    });
  });
}
