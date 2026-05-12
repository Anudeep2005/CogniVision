# CogniVision — Vision Aid App

> An AI-powered assistive application for visually impaired users, combining real-time voice interaction, GPS navigation, face recognition, and object detection in a single Flutter app.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Setup & Installation](#setup--installation)
  - [1. Clone the Repository](#1-clone-the-repository)
  - [2. Flutter App Setup](#2-flutter-app-setup)
  - [3. Backend Server Setup](#3-backend-server-setup)
  - [4. Firebase Setup](#4-firebase-setup)
  - [5. Environment Variables](#5-environment-variables)
- [Running the App](#running-the-app)
- [Backend API Reference](#backend-api-reference)
- [Key Dependencies](#key-dependencies)
- [Known Issues & Notes](#known-issues--notes)
- [Contributing](#contributing)

---

## Overview

CogniVision is a Flutter-based assistive app built for visually impaired users. It integrates three core modules accessible from a persistent bottom navigation bar:

| Tab | Name | Purpose |
|-----|------|---------|
| 1 | **Vertex AI** | Gemini 2.0 Live API — real-time voice + camera assistant |
| 2 | **GPS** | Voice-commanded walking navigation with turn-by-turn audio |
| 3 | **Face** | On-device face registration and recognition using MobileFaceNet |

The entire app is voice-navigable — users can switch tabs, trigger SOS alerts, and issue navigation commands by speaking.

---

## Features

### Vertex AI (Gemini Live)
- Real-time two-way audio conversation with Gemini 2.0 Flash
- Live camera feed streamed to Gemini for visual scene description
- YOLOv8n on-device object detection with spoken announcements (positions objects as "ahead / left / right")
- Session watchdog auto-restarts stale Gemini connections
- Audio plays through the device speaker (not earpiece)

### GPS Navigation
- Voice-triggered destination search ("navigate to Apollo Hospital")
- Walking route via Google Directions API with polyline overlay on Google Maps
- Live turn-by-turn audio instructions as the user walks
- Real-time location tracking broadcast to guardian via Socket.IO
- SOS voice command instantly alerts the linked guardian

### Face Recognition
- Uses the **back camera** so blind users can point it at people in front of them
- Registers faces with name + MobileFaceNet 192-d embedding stored in Hive (on-device)
- Cosine similarity matching (threshold ≥ 0.75) with confidence percentage
- Auto-scan mode continuously checks for faces every 300 ms
- Works fully offline — no server required for recognition

### Authentication
- Firebase Auth (email + password)
- Two roles: **User** (visually impaired person) and **Guardian** (caregiver)
- Role stored in MongoDB via a Node.js/Express backend
- Guardian dashboard shows real-time user location via Socket.IO

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App                       │
│                                                     │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │ Vertex   │  │  GPS / Maps  │  │     Face      │ │
│  │ AI Tab   │  │     Tab      │  │  Recognition  │ │
│  │          │  │              │  │     Tab       │ │
│  │ Gemini   │  │ Google Maps  │  │ MobileFaceNet │ │
│  │ Live API │  │ Directions   │  │ (TFLite)      │ │
│  │ YOLOv8n  │  │ Geolocator   │  │ Google ML Kit │ │
│  └──────────┘  └──────────────┘  └───────────────┘ │
│                                                     │
│         Global Voice Service (speech_to_text)       │
│         Global TTS Service    (flutter_tts)         │
└───────────────────────┬─────────────────────────────┘
                        │ HTTP / WebSocket
          ┌─────────────┴──────────────┐
          │     Node.js Backend        │
          │  Express + Socket.IO       │
          │  Firebase Admin SDK        │
          │  MongoDB (Mongoose)        │
          └────────────────────────────┘
```

---

## Project Structure

```
vision_aid_app/
├── lib/
│   └── src/
│       ├── face_features/           # Face recognition module
│       │   ├── camera_service.dart      # Back-camera capture + ML Kit face detection
│       │   ├── face_embedding_service.dart  # MobileFaceNet TFLite inference
│       │   ├── face_storage_service.dart    # Hive persistence + cosine matching
│       │   ├── home_screen.dart
│       │   ├── register_screen.dart
│       │   ├── recognize_screen.dart
│       │   ├── registered_faces_screen.dart
│       │   ├── registered_face.dart         # Hive model
│       │   └── registered_face.g.dart       # Generated adapter
│       │
│       ├── gps_features/
│       │   └── user/
│       │       ├── user_home_screen.dart    # Google Maps + live navigation UI
│       │       └── user_provider.dart       # Riverpod state (RouteState, AppMode)
│       │
│       ├── gps_core/
│       │   ├── navigation_service.dart  # Google Directions API + turn-by-turn logic
│       │   ├── command_router.dart      # Maps voice commands → navigation actions
│       │   └── socket_service.dart      # Socket.IO client (location + SOS)
│       │
│       ├── services/
│       │   ├── global_voice_service.dart  # STT + tab-switching voice commands
│       │   ├── tts_service.dart           # flutter_tts wrapper for YOLO announcements
│       │   └── api_service.dart           # HTTP client for backend auth
│       │
│       ├── utilities/
│       │   ├── audio_input.dart       # PCM mic recording stream
│       │   ├── audio_output.dart      # SoLoud PCM playback for Gemini audio
│       │   ├── video_input.dart       # Camera → JPEG stream for Gemini
│       │   └── yolo_detector.dart     # YOLOv8n TFLite inference + NMS
│       │
│       ├── ui_components/
│       │   ├── luxury_background.dart
│       │   ├── bottom_bar.dart
│       │   ├── branding.dart
│       │   ├── camera_previews.dart
│       │   ├── sound_waves.dart
│       │   ├── theme.dart
│       │   ├── vertical_switch.dart
│       │   └── ui_components.dart     # Barrel export
│       │
│       ├── screens/
│       │   ├── main_navigation_wrapper.dart  # Bottom nav + mic FAB
│       │   ├── login_screen.dart
│       │   ├── guardian_screen.dart
│       │   └── placeholder_screens.dart
│       │
│       ├── flutterfire_ai_live_api_demo.dart  # Gemini Live session orchestrator
│       ├── providers.dart                      # Riverpod global providers
│       └── firebase_options.dart               # Generated by FlutterFire CLI
│
├── assets/
│   └── models/
│       ├── yolov8n.tflite   # YOLOv8 nano model
│       └── yolov8n.txt      # COCO class labels
│
├── backend/                 # Node.js server
│   ├── config/
│   │   ├── db.js            # MongoDB connection
│   │   └── firebase.js      # Firebase Admin init
│   ├── middleware/
│   │   ├── requireAuth.js   # Firebase token verification
│   │   └── requireRole.js   # Role-based access guard
│   ├── models/
│   │   └── User.js          # Mongoose user schema
│   ├── routes/
│   │   └── auth.js          # POST /register, GET /me
│   └── index.js             # Express + Socket.IO entry point
│
├── .env                     # Environment variables (not committed)
├── firebase.json
└── pubspec.yaml
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | ≥ 3.4.0 |
| Dart SDK | ≥ 3.4.0 |
| Node.js | ≥ 18.x |
| MongoDB | Local or Atlas cluster |
| Firebase project | With Auth + Vertex AI enabled |
| Google Cloud | Maps SDK + Directions API enabled |

---

## Setup & Installation

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/cognivision.git
cd cognivision
```

### 2. Flutter App Setup

```bash
# Install Flutter dependencies
flutter pub get

# Generate Hive type adapters (run this whenever registered_face.dart changes)
dart run build_runner build --delete-conflicting-outputs
```

Download the MobileFaceNet model and place it in the project:

```bash
# The app auto-downloads it on first launch, but you can pre-cache it:
# https://github.com/ngtrphuong/facerecognition/raw/main/assets/mobilefacenet.tflite
```

YOLOv8n model must be manually placed:

```
assets/models/yolov8n.tflite
assets/models/yolov8n.txt
```

You can download the official nano model from [Ultralytics](https://github.com/ultralytics/ultralytics) and export it to TFLite format.

### 3. Backend Server Setup

```bash
cd backend
npm install
```

Create a `.env` file in the `backend/` folder:

```env
PORT=3000
MONGO_URI=mongodb://localhost:27017/cognivision
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_CLIENT_EMAIL=your-service-account@your-project.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

> The Firebase service account credentials come from **Firebase Console → Project Settings → Service Accounts → Generate new private key**.

Start the server:

```bash
node index.js
# Server running on port 3000
```

### 4. Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable **Authentication → Email/Password**
3. Enable **Vertex AI in Firebase** (for Gemini Live API access)
4. Run FlutterFire CLI to regenerate `firebase_options.dart` for your project:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

5. Place `google-services.json` in `android/app/` and `GoogleService-Info.plist` in `ios/Runner/`.

### 5. Environment Variables

Create a `.env` file in the **Flutter project root** (next to `pubspec.yaml`):

```env
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
```

> **Never commit `.env` or any file containing API keys.** The `.gitignore` already excludes secret files, but double-check before pushing.

Also update the hardcoded backend IP in the Flutter source to point to your server:

```dart
// lib/src/services/api_service.dart
static const String baseUrl = 'http://YOUR_SERVER_IP:3000/api';

// lib/src/gps_core/socket_service.dart
socket = IO.io('http://YOUR_SERVER_IP:3000', ...);
```

---

## Running the App

```bash
# Run on a connected Android or iOS device
flutter run

# Run with verbose logging (useful for Gemini session debugging)
flutter run -v
```

> The app requires a **physical device** — camera, microphone, and GPS do not work in the emulator.

#### Android permissions required (`AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

#### iOS permissions required (`Info.plist`)

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used for face recognition and visual AI assistance.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone is used for voice commands and AI conversation.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Location is used for GPS navigation.</string>
```

---

## Backend API Reference

Base URL: `http://your-server:3000`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/health` | None | Server health check |
| `POST` | `/api/auth/register` | None | Register a new user |
| `GET` | `/api/auth/me` | Bearer token | Get current user profile |

**POST `/api/auth/register`**

```json
{
  "firebaseUid": "uid-from-firebase",
  "role": "user",
  "displayName": "Anudeep Kumar",
  "email": "user@example.com"
}
```

Response `201`:
```json
{
  "_id": "...",
  "firebaseUid": "...",
  "role": "user",
  "displayName": "Anudeep Kumar",
  "email": "user@example.com"
}
```

**Socket.IO Events**

| Event | Direction | Payload |
|-------|-----------|---------|
| `join` | Client → Server | `userId: string` |
| `LOCATION_UPDATE` | Client → Server | `{ userId, lat, lng, timestamp }` |
| `LOCATION_UPDATE` | Server → Client | `{ userId, lat, lng, timestamp }` |
| `SOS_ALERT` | Client → Server | `{ userId, type: "SOS", status: "active" }` |
| `SOS_ALERT` | Server → Client | `{ userId, type: "SOS", status: "active" }` |

---

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `firebase_ai` | Gemini 2.0 Live API (Vertex AI) |
| `firebase_auth` | Email/password authentication |
| `flutter_riverpod` | State management |
| `record` | PCM microphone stream for Gemini |
| `flutter_soloud` | Low-latency PCM audio playback for Gemini responses |
| `speech_to_text` | Voice command recognition |
| `flutter_tts` | Text-to-speech for navigation and YOLO announcements |
| `google_maps_flutter` | Map display and route polyline |
| `geolocator` | Real-time GPS position stream |
| `flutter_polyline_points` | Decodes Google Directions polyline |
| `google_mlkit_face_detection` | On-device face bounding box detection |
| `tflite_flutter` | Runs MobileFaceNet + YOLOv8n on-device |
| `hive` / `hive_flutter` | Local face embedding storage |
| `socket_io_client` | Real-time location + SOS with the backend |
| `camera` | Camera stream for Gemini and YOLO |
| `flutter_dotenv` | Loads `.env` at runtime |

---

## Known Issues & Notes

- **MobileFaceNet model** (~2 MB) is downloaded automatically on first launch of the Face tab. Ensure internet access on first run.
- **YOLOv8n assets** must be manually placed in `assets/models/` before building — they are not auto-downloaded.
- The backend IP addresses (`10.70.4.162`) in `api_service.dart` and `socket_service.dart` are hardcoded for local network use. Replace with your production server URL before deploying.
- Gemini Live API (`gemini-2.0-flash-exp`) requires Vertex AI to be enabled in your Firebase project and may incur Google Cloud costs.
- The Google Maps API key must have **Maps SDK for Android/iOS** and **Directions API** enabled in Google Cloud Console.
- Face recognition uses the **back camera** — the app is designed for blind users pointing their phone at other people, not at themselves.
- On-device STT (`speech_to_text`) requires an active internet connection on most Android devices unless the on-device language pack is installed.

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m "feat: describe your change"`
4. Push to the branch: `git push origin feature/your-feature`
5. Open a Pull Request

Please make sure to run `flutter analyze` and `flutter test` before submitting a PR.

---

*Built with Flutter · Powered by Google Gemini · Designed for accessibility*
