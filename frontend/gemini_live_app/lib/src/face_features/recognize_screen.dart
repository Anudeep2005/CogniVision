import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'camera_service.dart';
import 'face_embedding_service.dart';
import 'face_storage_service.dart';

class RecognizeScreen extends StatefulWidget {
  final FaceEmbeddingService embeddingService;
  final FaceStorageService storageService;

  const RecognizeScreen({
    super.key,
    required this.embeddingService,
    required this.storageService,
  });

  @override
  State<RecognizeScreen> createState() => _RecognizeScreenState();
}

class _RecognizeScreenState extends State<RecognizeScreen> {
  final CameraService _cameraService = CameraService();

  bool _cameraReady = false;
  bool _processing  = false;
  RecognitionResult? _result;
  bool _isAutoScanning = false;
  String _statusMessage = 'Point camera at a face';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _statusMessage = 'Camera permission denied');
      return;
    }
    await _cameraService.initialize();
    if (mounted) {
      setState(() => _cameraReady = true);
      _toggleAutoScan(); // Automatically start scanning
    }
  }

  void _toggleAutoScan() {
    setState(() {
      _isAutoScanning = !_isAutoScanning;
    });
    if (_isAutoScanning) {
      _autoScanLoop();
    }
  }

  Future<void> _autoScanLoop() async {
    while (_isAutoScanning && mounted) {
      if (!_processing) {
        await _scanAndRecognize();
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _scanAndRecognize() async {
    if (_processing) return;
    if (widget.storageService.getAllFaces().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No faces registered yet. Please register first.')),
      );
      return;
    }
    if (!widget.embeddingService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model is still loading. Please wait…')),
      );
      return;
    }

    setState(() { _processing = true; _result = null; _statusMessage = 'Scanning…'; });

    // 1 – Capture photo
    final photo = await _cameraService.takePicture();
    if (photo == null) {
      setState(() { _processing = false; _statusMessage = 'Capture failed. Try again.'; });
      return;
    }

    // 2 – Detect faces (to get bounding box for cropping)
    final faces = await _cameraService.detectFacesInImage(photo);
    if (faces.isEmpty) {
      setState(() { _processing = false; _statusMessage = 'No face detected. Move closer.'; });
      return;
    }

    // 3 – Decode + crop the face region
    final bytes    = await File(photo.path).readAsBytes();
    final rawImage = img.decodeImage(bytes);
    if (rawImage == null) {
      setState(() { _processing = false; _statusMessage = 'Image error. Try again.'; });
      return;
    }

    final box = faces.first.boundingBox;
    final x = box.left  .clamp(0, rawImage.width  - 1).toInt();
    final y = box.top   .clamp(0, rawImage.height - 1).toInt();
    final w = box.width .clamp(1, rawImage.width  - x).toInt();
    final h = box.height.clamp(1, rawImage.height - y).toInt();

    final cropped   = img.copyCrop(rawImage, x: x, y: y, width: w, height: h);

    // 4 – Get TFLite embedding
    final embedding = await widget.embeddingService.getEmbedding(cropped);
    if (embedding == null) {
      setState(() { _processing = false; _statusMessage = 'Embedding failed. Try again.'; });
      return;
    }

    // 5 – Match against database
    final result = widget.storageService.findMatch(embedding);

    setState(() {
      _processing = false;
      _result = result;
      _statusMessage = result == null
          ? 'Matching failed'
          : result.isMatch
              ? 'Identity confirmed!'
              : 'Face not recognized';
    });
  }

  void _reset() {
    setState(() { _result = null; _statusMessage = 'Point camera at a face'; });
  }

  @override
  void dispose() {
    _isAutoScanning = false;
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Recognize Face',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_cameraReady && _cameraService.controller != null)
                  SizedBox.expand(child: CameraPreview(_cameraService.controller!))
                else
                  const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),

                // Oval guide frame
                Center(
                  child: Container(
                    width: 260, height: 320,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _result == null
                            ? const Color(0xFF00E5FF)
                            : _result!.isMatch
                                ? const Color(0xFF69FF8E)
                                : const Color(0xFFFF5252),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(140),
                    ),
                    child: _result != null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _result!.isMatch ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                color: _result!.isMatch ? const Color(0xFF69FF8E) : const Color(0xFFFF5252),
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _result!.isMatch ? _result!.face!.name : 'Unknown Person',
                                style: TextStyle(
                                  color: _result!.isMatch ? const Color(0xFF69FF8E) : const Color(0xFFFF5252),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Confidence: ${(_result!.confidence * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.white, 
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),

                // Status bar
                Positioned(
                  bottom: 16, left: 24, right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _result == null
                              ? Colors.white
                              : _result!.isMatch ? const Color(0xFF69FF8E) : const Color(0xFFFF5252),
                          fontSize: 13, fontWeight: FontWeight.w500,
                        )),
                  ),
                ),
              ],
            ),
          ),

          Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cameraReady ? _toggleAutoScan : null,
                    icon: Icon(_isAutoScanning ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded),
                    label: Text(_isAutoScanning ? 'Stop Auto-Scan' : 'Start Auto-Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAutoScanning ? const Color(0xFFFF5252) : const Color(0xFF69FF8E),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}
