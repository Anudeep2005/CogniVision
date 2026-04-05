import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

class AudioInput extends ChangeNotifier {
  final _recorder = AudioRecorder();
  RecordConfig recordConfig = const RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    echoCancel: true,
    noiseSuppress: true,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication,
    ),
    iosConfig: IosRecordConfig(categoryOptions: []),
  );
  bool isRecording = false;
  bool isPaused = false;

  Future<void> init() async {
    await checkPermission();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> checkPermission() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw MicrophonePermissionDeniedException(
        'This app does not have microphone permissions. Please enable it.',
      );
    }
  }

  Future<Stream<Uint8List>> startRecordingStream() async {
    final audioStream =
        (await _recorder.startStream(recordConfig)).asBroadcastStream();
    isRecording = true;
    notifyListeners();
    return audioStream;
  }

  Future<void> stopRecording() async {
    await _recorder.stop();
    isRecording = false;
    notifyListeners();
  }

  Future<void> togglePauseRecording() async {
    isPaused ? await _recorder.resume() : await _recorder.pause();
    isPaused = !isPaused;
    notifyListeners();
  }
}

class MicrophonePermissionDeniedException implements Exception {
  final String? message;
  MicrophonePermissionDeniedException([this.message]);

  @override
  String toString() {
    if (message == null) return 'MicrophonePermissionDeniedException';
    return 'MicrophonePermissionDeniedException: $message';
  }
}