import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class DetectionResult {
  final String label;
  final double confidence;
  final List<double> boundingBox; // [x, y, w, h] normalized

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });
}

class YoloDetector {
  Interpreter? _interpreter;
  List<String>? _labels;

  Future<void> init() async {
    try {
      _interpreter =
          await Interpreter.fromAsset('assets/models/yolov8n.tflite');
      final labelsData =
          await rootBundle.loadString('assets/models/yolov8n.txt');
      _labels = labelsData.split('\n').where((s) => s.isNotEmpty).toList();
      print('YOLO Detector initialized');
    } catch (e) {
      print('Error initializing YOLO Detector: $e');
    }
  }

  Future<List<DetectionResult>> detect(Uint8List jpegBytes) async {
    if (_interpreter == null || _labels == null) return [];

    try {
      // 1. Preprocessing: Decode and resize
      img.Image? image = img.decodeImage(jpegBytes);
      if (image == null) return [];

      img.Image resized = img.copyResize(image, width: 640, height: 640);

      // 2. Prepare Input Buffer [1, 640, 640, 3]
      var input = Float32List(1 * 640 * 640 * 3);
      for (int y = 0; y < 640; y++) {
        for (int x = 0; x < 640; x++) {
          final pixel = resized.getPixel(x, y);
          final int index = (y * 640 + x) * 3;
          // YOLOv8 expects normalized floats [0, 1]
          input[index] = pixel.r / 255.0;
          input[index + 1] = pixel.g / 255.0;
          input[index + 2] = pixel.b / 255.0;
        }
      }

      // 3. Prepare Output Buffer [1, 84, 8400]
      // Using a flat list for better performance and compatibility
      var output = Float32List(1 * 84 * 8400);

      // 4. Run Inference
      _interpreter!
          .run(input.reshape([1, 640, 640, 3]), output.reshape([1, 84, 8400]));

      // 5. Post-processing: Parse YOLOv8 output
      List<DetectionResult> results = [];
      final int numClasses = _labels!.length;

      // YOLOv8 output is (1, 84, 8400)
      // The 84 values at each of the 8400 positions are:
      // [cx, cy, w, h, class0_conf, class1_conf, ..., class79_conf]
      for (int i = 0; i < 8400; i++) {
        double maxConf = 0.0;
        int classId = -1;

        // Find best class match
        for (int j = 0; j < numClasses; j++) {
          // Index calculation for flat array: (channel * 8400) + position
          double conf = output[(4 + j) * 8400 + i];
          if (conf > maxConf) {
            maxConf = conf;
            classId = j;
          }
        }

        if (maxConf > 0.45) {
          double cx = output[0 * 8400 + i];
          double cy = output[1 * 8400 + i];
          double w = output[2 * 8400 + i];
          double h = output[3 * 8400 + i];

          // Normalize coordinates to [0, 1] based on 640 model input
          results.add(DetectionResult(
            label: _labels![classId],
            confidence: maxConf,
            boundingBox: [cx / 640, cy / 640, w / 640, h / 640],
          ));
        }
      }

      // 6. Non-Maximum Suppression (NMS)
      results.sort((a, b) => b.confidence.compareTo(a.confidence));

      List<DetectionResult> nmsResults = [];
      for (var res in results) {
        bool keep = true;
        for (var kept in nmsResults) {
          if (res.label == kept.label) {
            double iou = _calculateIoU(res.boundingBox, kept.boundingBox);
            if (iou > 0.45) {
              keep = false;
              break;
            }
          }
        }
        if (keep) {
          nmsResults.add(res);
        }
        if (nmsResults.length >= 5) break;
      }

      return nmsResults;
    } catch (e) {
      print('Detection Error: $e');
      return [];
    }
  }

  double _calculateIoU(List<double> box1, List<double> box2) {
    // box1/2 = [cx, cy, w, h]
    double b1x1 = box1[0] - box1[2] / 2;
    double b1y1 = box1[1] - box1[3] / 2;
    double b1x2 = box1[0] + box1[2] / 2;
    double b1y2 = box1[1] + box1[3] / 2;

    double b2x1 = box2[0] - box2[2] / 2;
    double b2y1 = box2[1] - box2[3] / 2;
    double b2x2 = box2[0] + box2[2] / 2;
    double b2y2 = box2[1] + box2[3] / 2;

    double x1 = b1x1 > b2x1 ? b1x1 : b2x1;
    double y1 = b1y1 > b2y1 ? b1y1 : b2y1;
    double x2 = b1x2 < b2x2 ? b1x2 : b2x2;
    double y2 = b1y2 < b2y2 ? b1y2 : b2y2;

    double width = x2 - x1;
    double height = y2 - y1;

    if (width <= 0 || height <= 0) return 0.0;

    double intersection = width * height;
    double union = (box1[2] * box1[3]) + (box2[2] * box2[3]) - intersection;

    return intersection / union;
  }

  void dispose() {
    _interpreter?.close();
  }
}
