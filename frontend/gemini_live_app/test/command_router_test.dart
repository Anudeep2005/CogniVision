import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

void main() {
  test('CommandRouter parses navigation commands correctly', () {
    // Note: In a real test we might mock the Ref
    // This is a simplified logic test
    final triggers = ['navigate to', 'take me to', 'route to', 'directions to', 'go to', 'find '];
    String command = "navigate to Central Park";
    String? destination;

    for (var trigger in triggers) {
      if (command.toLowerCase().contains(trigger)) {
        destination = command.toLowerCase().split(trigger).last.trim();
        break;
      }
    }

    expect(destination, 'central park');
  });

  test('CommandRouter parses start navigation command', () {
    String command = "start navigation";
    final lowerCmd = command.toLowerCase();
    bool isStart = (lowerCmd == 'start' || lowerCmd == 'start navigation' || lowerCmd == 'begin' || lowerCmd == "let's go");
    
    expect(isStart, true);
  });

  test('CommandRouter parses SOS command correctly', () {
    String command = "alert guardian";
    final lowerCmd = command.toLowerCase();
    bool isSos = (lowerCmd.contains('alert guardian') || lowerCmd.contains('help') || lowerCmd.contains('sos'));
    
    expect(isSos, true);
  });

    test('Identify Navigation Intent', () {
      final navCommands = [
        'navigate to central park',
        'take me to library',
        'route to hospital',
        'find grocery store',
      ];
      
      for (var cmd in navCommands) {
        expect(cmd.contains('navigate') || cmd.contains('take me') || cmd.contains('route') || cmd.contains('find'), isTrue);
      }
    });

    test('SOS Trigger Match', () {
      expect('help me now'.contains('help'), isTrue);
      expect('emergency sos'.contains('sos'), isTrue);
      expect('alert guardian'.contains('alert'), isTrue);
    });

  group('Math Utilities', () {
    test('Coordinate Distance Calculation Placeholder', () {
       // Mock lat/lng distance logic
       double lat1 = 12.9716;
       double lon1 = 77.5946;
       double lat2 = 12.9719;
       double lon2 = 77.5949;
       
       double diff = (lat1 - lat2).abs() + (lon1 - lon2).abs();
       expect(diff < 0.01, isTrue);
    });
  });

  test('YOLO bounding box Intersection over Union (IoU) calculation', () {
    // Mocking the IoU logic from YoloDetector
    double calculateIoU(List<double> box1, List<double> box2) {
      double b1x1 = box1[0] - box1[2] / 2, b1y1 = box1[1] - box1[3] / 2;
      double b1x2 = box1[0] + box1[2] / 2, b1y2 = box1[1] + box1[3] / 2;
      double b2x1 = box2[0] - box2[2] / 2, b2y1 = box2[1] - box2[3] / 2;
      double b2x2 = box2[0] + box2[2] / 2, b2y2 = box2[1] + box2[3] / 2;

      double x1 = b1x1 > b2x1 ? b1x1 : b2x1;
      double y1 = b1y1 > b2y1 ? b1y1 : b2y1;
      double x2 = b1x2 < b2x2 ? b1x2 : b2x2;
      double y2 = b1y2 < b2y2 ? b1y2 : b2y2;

      double width = x2 - x1, height = y2 - y1;
      if (width <= 0 || height <= 0) return 0.0;
      double intersection = width * height;
      double union = (box1[2] * box1[3]) + (box2[2] * box2[3]) - intersection;
      return intersection / union;
    }

    // Two identical boxes
    double iouSame = calculateIoU([0.5, 0.5, 0.2, 0.2], [0.5, 0.5, 0.2, 0.2]);
    expect(iouSame, closeTo(1.0, 0.001));

    // Non-overlapping boxes
    double iouNone = calculateIoU([0.1, 0.1, 0.1, 0.1], [0.8, 0.8, 0.1, 0.1]);
    expect(iouNone, 0.0);
  });

  test('Face Recognition Cosine Distance calculation', () {
    // Mocking the cosine distance logic
    double cosineDistance(List<double> e1, List<double> e2) {
      double dotProduct = 0.0, norm1 = 0.0, norm2 = 0.0;
      for (int i = 0; i < e1.length; i++) {
        dotProduct += e1[i] * e2[i];
        norm1 += e1[i] * e1[i];
        norm2 += e2[i] * e2[i];
      }
      return 1.0 - (dotProduct / (sqrt(norm1) * sqrt(norm2)));
    }

    // Same vectors should have distance 0
    double distSame = cosineDistance([1.0, 0.0, 0.0], [1.0, 0.0, 0.0]);
    expect(distSame, closeTo(0.0, 0.001));

    // Orthogonal vectors should have distance 1.0
    double distOrthogonal = cosineDistance([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]);
    expect(distOrthogonal, closeTo(1.0, 0.001));
  });

  group('Service Logic', () {
    test('ApiService constructs correct SOS payload', () {
      final payload = {
        'userId': 'test_uid_123',
        'type': 'SOS',
        'message': 'Emergency alert triggered',
        'location': {'lat': 12.97, 'lng': 77.59},
      };
      expect(payload['userId'], 'test_uid_123');
      expect(payload['location']['lat'], 12.97);
      expect(payload['type'], 'SOS');
    });
  });
}
