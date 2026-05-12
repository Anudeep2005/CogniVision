import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'camera_service.dart';
import 'face_embedding_service.dart';
import 'face_storage_service.dart';

class RegisterScreen extends StatefulWidget {
  final FaceEmbeddingService embeddingService;
  final FaceStorageService storageService;

  const RegisterScreen({
    super.key,
    required this.embeddingService,
    required this.storageService,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final CameraService _cameraService = CameraService();
  final TextEditingController _nameController = TextEditingController();

  bool _cameraReady = false;
  bool _processing = false;
  bool _faceCaptured = false;
  XFile? _capturedImage;
  List<Face> _faces = [];
  String _statusMessage = 'Position your face in the frame';

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
    if (mounted) setState(() => _cameraReady = true);
  }

  Future<void> _captureAndDetect() async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _statusMessage = 'Detecting face…';
    });

    final photo = await _cameraService.takePicture();
    if (photo == null) {
      setState(() { _processing = false; _statusMessage = 'Failed to capture. Try again.'; });
      return;
    }

    final faces = await _cameraService.detectFacesInImage(photo);
    if (faces.isEmpty) {
      setState(() { _processing = false; _statusMessage = 'No face detected. Try again.'; });
      return;
    }

    setState(() {
      _capturedImage = photo;
      _faces = faces;
      _faceCaptured = true;
      _processing = false;
      _statusMessage = 'Face detected! Enter your name to register.';
    });
  }

  Future<void> _registerFace() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }

    if (!widget.embeddingService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model is still loading. Please wait…')),
      );
      return;
    }

    setState(() { _processing = true; _statusMessage = 'Extracting face embedding…'; });

    final bytes    = await File(_capturedImage!.path).readAsBytes();
    final rawImage = img.decodeImage(bytes);
    if (rawImage == null) {
      setState(() { _processing = false; _statusMessage = 'Image decoding failed. Try again.'; });
      return;
    }

    final face = _faces.first;
    final box  = face.boundingBox;
    final x = box.left.clamp(0, rawImage.width  - 1).toInt();
    final y = box.top .clamp(0, rawImage.height - 1).toInt();
    final w = box.width .clamp(1, rawImage.width  - x).toInt();
    final h = box.height.clamp(1, rawImage.height - y).toInt();

    final cropped   = img.copyCrop(rawImage, x: x, y: y, width: w, height: h);
    final embedding = await widget.embeddingService.getEmbedding(cropped);

    if (embedding == null) {
      setState(() { _processing = false; _statusMessage = 'Could not compute embedding. Try again.'; });
      return;
    }

    await widget.storageService.registerFace(name: name, embedding: embedding);

    if (mounted) {
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name registered successfully!'),
          backgroundColor: const Color(0xFF69FF8E).withOpacity(0.9),
        ),
      );
      Navigator.pop(context);
    }
  }

  void _retake() {
    setState(() {
      _capturedImage = null;
      _faces = [];
      _faceCaptured = false;
      _statusMessage = 'Position your face in the frame';
    });
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Register Face',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_faceCaptured && _capturedImage != null)
                  Container(
                    width: double.infinity,
                    color: Colors.black,
                    child: Image.file(File(_capturedImage!.path), fit: BoxFit.cover),
                  )
                else if (_cameraReady && _cameraService.controller != null)
                  SizedBox.expand(child: CameraPreview(_cameraService.controller!))
                else
                  const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),

                if (!_faceCaptured)
                  Center(
                    child: Container(
                      width: 240, height: 300,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF00E5FF), width: 2),
                        borderRadius: BorderRadius.circular(140),
                      ),
                    ),
                  ),

                Positioned(
                  bottom: 20, left: 24, right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),

          Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: _faceCaptured
                ? Column(children: [
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter full name',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1C1C1C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.person_outline, color: Colors.white38),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _retake,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white54,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Retake'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _processing ? null : _registerFace,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _processing
                              ? const SizedBox(height: 18, width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Text('Register', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ])
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_cameraReady && !_processing) ? _captureAndDetect : null,
                      icon: _processing
                          ? const SizedBox(height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.camera_alt_rounded),
                      label: Text(_processing ? 'Detecting…' : 'Capture Face'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
