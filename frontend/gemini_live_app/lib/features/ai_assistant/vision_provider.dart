import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';

final cameraControllerProvider = StateProvider<CameraController?>((ref) => null);

enum VisionAction { none, describe }
final visionActionProvider = StateProvider<VisionAction>((ref) => VisionAction.none);
