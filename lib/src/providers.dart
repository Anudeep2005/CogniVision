import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'utilities/audio_input.dart';
import 'utilities/audio_output.dart';
import 'utilities/video_input.dart';

final audioInputProvider = ChangeNotifierProvider<AudioInput>((ref) {
  return AudioInput();
});

final videoInputProvider = ChangeNotifierProvider<VideoInput>((ref) {
  return VideoInput();
});

final audioOutputProvider = Provider<AudioOutput>((ref) {
  return AudioOutput();
});