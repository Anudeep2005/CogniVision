import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'utilities/audio_input.dart';
import 'utilities/audio_output.dart';
import 'utilities/video_input.dart';

/// Available AI operation modes in CogniVision.
enum AiMode {
  /// Real on-device object detection with directional TTS spatial announcements.
  localYolo,

  /// Cloud-based multimodal streaming assistant with Vertex / Gemini Live.
  cloudGemini,
}

/// Lifecycle and transition states for mode switching.
enum ModeTransitionState {
  /// Subsystems are halted or idle (e.g., backgrounded tab).
  idle,

  /// In the middle of tearing down one mode and setting up another.
  transitioning,

  /// Subsystem is active and operational.
  active,

  /// An error occurred during mode setup or connection.
  error,
}

/// Authoritative provider for the current AI mode (safe offline default: localYolo).
final aiModeProvider = StateProvider<AiMode>((ref) => AiMode.localYolo);

/// Authoritative provider for tracking mode transitions and mutual exclusion.
final modeTransitionProvider =
    StateProvider<ModeTransitionState>((ref) => ModeTransitionState.idle);

final audioInputProvider = ChangeNotifierProvider<AudioInput>((ref) {
  return AudioInput();
});

final videoInputProvider = ChangeNotifierProvider<VideoInput>((ref) {
  return VideoInput();
});

final audioOutputProvider = Provider<AudioOutput>((ref) {
  return AudioOutput();
});

final userRoleProvider = StateProvider<String?>((ref) => null);

final vertexActiveProvider = StateProvider<bool>((ref) => false);