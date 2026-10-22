import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../utilities/yolo_detector.dart';

class TtsService {
  final FlutterTts _flutterTts;
  bool _isSpeaking = false;
  bool _isInitialized = false;
  DateTime? _lastAnnouncementTime;
  String? _lastSpokenPhrase;

  // Rate-limiting and deduplication durations
  final Duration cooldown;
  final Duration repeatCooldown;

  TtsService({
    FlutterTts? flutterTts,
    this.cooldown = const Duration(milliseconds: 3000),
    this.repeatCooldown = const Duration(milliseconds: 6000),
  }) : _flutterTts = flutterTts ?? FlutterTts();

  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _isInitialized;
  DateTime? get lastAnnouncementTime => _lastAnnouncementTime;
  String? get lastSpokenPhrase => _lastSpokenPhrase;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        debugPrint('[TtsService] TTS error: $msg');
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('[TtsService] Initialization error: $e');
    }
  }

  /// Maps normalized bounding box horizontal center [centerX] to spatial direction string.
  /// Binning thresholds:
  /// - cx < 0.33  -> "on your left"
  /// - cx > 0.66  -> "on your right"
  /// - 0.33..0.66 -> "ahead"
  static String getDirection(double centerX) {
    if (centerX < 0.33) {
      return "on your left";
    } else if (centerX > 0.66) {
      return "on your right";
    } else {
      return "ahead";
    }
  }

  /// Constructs a concise, grammatical, non-repetitive spatial announcement
  /// from the top detected obstacles.
  /// Takes at most the top 2 highest-confidence detections.
  /// Returns null if detections are empty or no phrase should be spoken.
  static String? buildSpatialAnnouncement(List<DetectionResult> detections) {
    if (detections.isEmpty) return null;

    // Take top 2 highest-confidence detections
    final items = detections.take(2).toList();

    if (items.length == 1) {
      final det = items[0];
      final dir = getDirection(det.boundingBox[0]);
      return "${_capitalize(det.label)} $dir.";
    } else {
      final d1 = items[0];
      final d2 = items[1];
      final dir1 = getDirection(d1.boundingBox[0]);
      final dir2 = getDirection(d2.boundingBox[0]);

      if (dir1 == dir2) {
        // Same direction: "Person and chair ahead."
        return "${_capitalize(d1.label)} and ${d2.label} $dir1.";
      } else {
        // Different directions: "Person ahead, and chair on your left."
        return "${_capitalize(d1.label)} $dir1, and ${d2.label} $dir2.";
      }
    }
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Determines whether [newPhrase] should be spoken given cooldown and repeat suppression rules.
  static bool shouldAnnounce({
    required String? newPhrase,
    required String? lastPhrase,
    required DateTime? lastSpokenTime,
    required DateTime currentTime,
    required bool isSpeaking,
    Duration cooldown = const Duration(milliseconds: 3000),
    Duration repeatCooldown = const Duration(milliseconds: 6000),
  }) {
    if (newPhrase == null || newPhrase.isEmpty) return false;
    if (isSpeaking) return false;

    if (lastSpokenTime != null) {
      final elapsed = currentTime.difference(lastSpokenTime);
      if (elapsed < cooldown) {
        return false;
      }
      if (newPhrase == lastPhrase && elapsed < repeatCooldown) {
        return false;
      }
    }

    return true;
  }

  /// Evaluates detections, applies spatial binning, cooldown, and repeat suppression,
  /// then triggers speech if eligible.
  Future<void> announceDetections(
    List<DetectionResult> detections, {
    DateTime? testCurrentTime,
  }) async {
    if (detections.isEmpty) return;

    final phrase = buildSpatialAnnouncement(detections);
    if (phrase == null) return;

    final now = testCurrentTime ?? DateTime.now();

    final eligible = shouldAnnounce(
      newPhrase: phrase,
      lastPhrase: _lastSpokenPhrase,
      lastSpokenTime: _lastAnnouncementTime,
      currentTime: now,
      isSpeaking: _isSpeaking,
      cooldown: cooldown,
      repeatCooldown: repeatCooldown,
    );

    if (!eligible) return;

    _lastAnnouncementTime = now;
    _lastSpokenPhrase = phrase;
    await speak(phrase);
  }

  Future<void> speak(String text) async {
    try {
      _isSpeaking = true;
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      _isSpeaking = false;
      debugPrint('[TtsService] Speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('[TtsService] Stop error: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  /// Resets timing and phrase history (e.g. when entering YOLO mode)
  void reset() {
    _lastAnnouncementTime = null;
    _lastSpokenPhrase = null;
    _isSpeaking = false;
  }

  void dispose() {
    stop();
    reset();
  }
}
