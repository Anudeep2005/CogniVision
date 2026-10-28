import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../utilities/yolo_detector.dart';

class TtsService {
  final FlutterTts _flutterTts;
  bool _isSpeaking = false;
  bool _isInitialized = false;
  DateTime? _lastAnnouncementTime;
  String? _lastSpokenPhrase;

  // Set of labels present in the previous detection frame — used for the
  // "newly appeared" urgency override.
  Set<String> _previousLabels = {};

  // Rate-limiting and deduplication durations
  final Duration cooldown;
  final Duration repeatCooldown;

  TtsService({
    FlutterTts? flutterTts,
    this.cooldown = const Duration(milliseconds: 4000),
    this.repeatCooldown = const Duration(milliseconds: 8000),
  }) : _flutterTts = flutterTts ?? FlutterTts();

  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _isInitialized;
  DateTime? get lastAnnouncementTime => _lastAnnouncementTime;
  String? get lastSpokenPhrase => _lastSpokenPhrase;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage("en-US");
      // 0.5 is the default but we drop to 0.45 for slightly clearer articulation
      // on noisy environments; still fast enough for real-time use.
      await _flutterTts.setSpeechRate(0.45);
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

  /// Returns the correct form of "to be" for [count] items.
  static String _verb(int count) => count == 1 ? 'is' : 'are';

  /// Returns the indefinite article for [label] ("a" or "an").
  static String _article(String label) {
    const vowelStarts = {'a', 'e', 'i', 'o', 'u'};
    return (label.isNotEmpty && vowelStarts.contains(label[0].toLowerCase()))
        ? 'an'
        : 'a';
  }

  /// Pluralises [label] naively (appends "s").
  static String _plural(String label) => '${label}s';

  /// Constructs a concise, grammatical, natural-language spatial announcement
  /// from the top detected obstacles.
  ///
  /// Examples:
  ///   1 person ahead            → "A person is ahead."
  ///   2 people ahead            → "Two people are ahead."
  ///   person left + chair ahead → "A person is on your left, and a chair is ahead."
  ///   person + chair both ahead → "A person and a chair are ahead."
  static String? buildSpatialAnnouncement(List<DetectionResult> detections) {
    if (detections.isEmpty) return null;

    // Group by label and direction: take the top 2 by confidence.
    final items = detections.take(2).toList();

    if (items.length == 1) {
      final det = items[0];
      final dir = getDirection(det.boundingBox[0]);
      final art = _article(det.label);
      return "${_capitalize(art)} ${det.label} is $dir.";
    }

    final d1 = items[0];
    final d2 = items[1];
    final dir1 = getDirection(d1.boundingBox[0]);
    final dir2 = getDirection(d2.boundingBox[0]);

    if (d1.label == d2.label) {
      // Same class: "Two people are ahead." / "Two people are on your left."
      if (dir1 == dir2) {
        return "Two ${_plural(d1.label)} ${_verb(2)} $dir1.";
      } else {
        return "Two ${_plural(d1.label)} — one $dir1, one $dir2.";
      }
    }

    if (dir1 == dir2) {
      // Different labels, same direction: "A person and a chair are ahead."
      final art2 = _article(d2.label);
      return "${_capitalize(_article(d1.label))} ${d1.label} and $art2 ${d2.label} are $dir1.";
    } else {
      // Different labels, different directions:
      // "A person is ahead, and a chair is on your left."
      final art2 = _article(d2.label);
      return "${_capitalize(_article(d1.label))} ${d1.label} is $dir1, and $art2 ${d2.label} is $dir2.";
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
    Duration cooldown = const Duration(milliseconds: 4000),
    Duration repeatCooldown = const Duration(milliseconds: 8000),
    bool hasNewlyAppearedLabel = false,
    bool hasDirectionChanged = false,
  }) {
    if (newPhrase == null || newPhrase.isEmpty) return false;
    if (isSpeaking) return false;

    if (lastSpokenTime != null) {
      final elapsed = currentTime.difference(lastSpokenTime);
      // Bypass cooldown if the spatial direction has changed or a new label appeared.
      if ((hasNewlyAppearedLabel || hasDirectionChanged) && newPhrase != lastPhrase) {
        return true;
      }
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
    if (detections.isEmpty) {
      _previousLabels = {};
      return;
    }

    final phrase = buildSpatialAnnouncement(detections);
    if (phrase == null) return;

    final now = testCurrentTime ?? DateTime.now();

    // Detect any labels that weren't in the previous frame.
    final currentLabels = detections.map((d) => d.label).toSet();
    final hasNewlyAppearedLabel =
        currentLabels.any((l) => !_previousLabels.contains(l));
    _previousLabels = currentLabels;

    // Detect direction change: same label set as last announcement but phrase
    // differs means the object moved (e.g. left → ahead → right).
    final hasDirectionChanged = _lastSpokenPhrase != null &&
        phrase != _lastSpokenPhrase &&
        !hasNewlyAppearedLabel;

    final eligible = shouldAnnounce(
      newPhrase: phrase,
      lastPhrase: _lastSpokenPhrase,
      lastSpokenTime: _lastAnnouncementTime,
      currentTime: now,
      isSpeaking: _isSpeaking,
      cooldown: cooldown,
      repeatCooldown: repeatCooldown,
      hasNewlyAppearedLabel: hasNewlyAppearedLabel,
      hasDirectionChanged: hasDirectionChanged,
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
    _previousLabels = {};
  }

  void dispose() {
    stop();
    reset();
  }
}
