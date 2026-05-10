import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

class FaceRecognitionService {
  late FaceDetector _faceDetector;
  Interpreter? _interpreter;
  late Box _faceBox;
  bool _isInitialized = false;

  static final FaceRecognitionService _instance = FaceRecognitionService._internal();
  factory FaceRecognitionService() => _instance;
  FaceRecognitionService._internal();

  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Initialize Face Detector
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
    );
    _faceDetector = FaceDetector(options: options);

    // 2. Initialize TFLite Interpreter (MobileFaceNet)
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      debugPrint('MobileFaceNet Model Loaded successfully');
    } catch (e) {
      debugPrint('Failed to load MobileFaceNet model: $e');
    }

    // 3. Initialize Hive Box for storing faces
    await Hive.initFlutter();
    _faceBox = await Hive.openBox('known_faces');

    _isInitialized = true;
  }

  Future<List<Face>> detectFaces(InputImage inputImage) async {
    return await _faceDetector.processImage(inputImage);
  }

  // Convert image part to embedding
  Future<List<double>?> getEmbedding(img.Image faceImage) async {
    if (_interpreter == null) return null;

    // MobileFaceNet expects 112x112 input
    img.Image resizedImage = img.copyResize(faceImage, width: 112, height: 112);
    
    // Normalize image to [-1, 1] or [0, 1] based on model requirements
    // MobileFaceNet usually expects normalized floating point input
    var input = Float32List(1 * 112 * 112 * 3);
    var buffer = Float32List.view(input.buffer);
    int pixelIndex = 0;
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        var pixel = resizedImage.getPixel(x, y);
        buffer[pixelIndex++] = (img.getRed(pixel) - 127.5) / 128.0;
        buffer[pixelIndex++] = (img.getGreen(pixel) - 127.5) / 128.0;
        buffer[pixelIndex++] = (img.getBlue(pixel) - 127.5) / 128.0;
      }
    }

    var output = Float32List(1 * 192).reshape([1, 192]);
    _interpreter!.run(input.reshape([1, 112, 112, 3]), output);
    
    return List<double>.from(output[0]);
  }

  // Register a new face
  Future<void> registerFace(String name, List<double> embedding) async {
    await _faceBox.put(name, embedding);
  }

  // Search for a matching face
  String? identifyFace(List<double> embedding) {
    double minDistance = 1.0; // Cosine similarity threshold
    String? matchedName;

    for (var key in _faceBox.keys) {
      List<double> storedEmbedding = List<double>.from(_faceBox.get(key));
      double distance = _cosineDistance(embedding, storedEmbedding);
      
      if (distance < 0.6 && distance < minDistance) { // 0.6 is a common threshold for MobileFaceNet
        minDistance = distance;
        matchedName = key as String;
      }
    }

    return matchedName;
  }

  double _cosineDistance(List<double> e1, List<double> e2) {
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    for (int i = 0; i < e1.length; i++) {
      dotProduct += e1[i] * e2[i];
      norm1 += e1[i] * e1[i];
      norm2 += e2[i] * e2[i];
    }
    return 1.0 - (dotProduct / (sqrt(norm1) * sqrt(norm2)));
  }

  void dispose() {
    _faceDetector.close();
    _interpreter?.close();
  }
}

final faceRecognitionService = FaceRecognitionService();
