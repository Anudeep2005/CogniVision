# CogniVision — AI-Powered Vision Aid App

> A fully voice-navigable Flutter mobile application for visually impaired users, combining real-time Gemini 2.0 Live AI assistance, on-device YOLOv8n object detection, offline face recognition with MobileFaceNet, and GPS walking navigation — all in one app, controllable entirely by voice.

---

## Table of Contents

- [Problem Statement](#problem-statement)
- [Features](#features)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Setup & Installation](#setup--installation)
- [Running the App](#running-the-app)
- [Backend API Reference](#backend-api-reference)
- [Key Dependencies](#key-dependencies)
- [Known Issues & Notes](#known-issues--notes)
- [Future Enhancements](#future-enhancements)
- [Contributing](#contributing)

---

## Problem Statement

Visually impaired individuals must juggle multiple fragmented apps to navigate, identify people, and understand their surroundings — all without reliable vision. CogniVision solves this by combining Gemini Live AI, GPS turn-by-turn navigation, and on-device face recognition into a single, fully voice-controlled app. No screen interaction is required.

---

## Features

### 1. Vertex AI Tab — Gemini 2.0 Live Assistant
- **Real-time two-way audio** with Gemini 2.0 Flash via Firebase AI Live API
- **Live camera stream** (JPEG frames) sent to Gemini for visual scene description
- **PCM microphone capture** piped directly to Gemini; Gemini audio response played via SoLoud (low-latency PCM playback, not earpiece)
- **YOLOv8n on-device object detection** — 640×640 TFLite inference with full preprocessing, output tensor parsing, NMS (IoU 0.45), confidence threshold 0.45, top-5 results announced by relative position ("person ahead", "chair to the left")
- **Session watchdog** auto-restarts stale Gemini connections
- Microphone handed back to the global VoiceService when tab is inactive

### 2. GPS Navigation Tab
- **Voice-triggered destination** — say "navigate to Apollo Hospital" and the route is fetched
- **Google Directions API** (walking mode) called from current GPS fix via `geolocator`
- **Polyline overlay** on Google Maps with route bounds auto-fitted to camera
- **Turn-by-turn TTS** — HTML instructions stripped via `html` package; next step announced when within **15 metres** of the manoeuvre point
- **Arrival detection** — "You have arrived at your destination" spoken on reaching the last waypoint
- **Real-time location broadcast** to linked guardian via Socket.IO `LOCATION_UPDATE` event
- **SOS voice command** emits `SOS_ALERT` via Socket.IO to the guardian's room instantly

### 3. Face Recognition Tab
- **Back camera** used intentionally — blind users point the phone at the person in front
- **Google ML Kit** detects face bounding boxes per frame
- **MobileFaceNet TFLite** (`[1, 112, 112, 3]` input → `[1, 192]` output) extracts L2-normalised 192-d embeddings
- **Cosine similarity matching** against Hive-stored embeddings; threshold ≥ **0.75** = confirmed match
- **Registration** — name + UUID + embedding stored on-device in Hive
- **Auto-scan mode** continuously recognises every 300 ms
- **Fully offline** — zero network calls for recognition after first model download (~2 MB)
- Registered faces list with delete and clear-all options

### 4. Voice Command System (Global)
- Single `VoiceService` singleton using `speech_to_text`
- Tab switching by spoken keyword: *"vertex / AI / assistant"* → tab 0 · *"GPS / navigate"* → tab 1 · *"face / recognition"* → tab 2
- Haptic feedback on microphone activation
- Microphone arbitration prevents conflict with Gemini Live session

### 5. Authentication & Roles
- **Firebase Auth** (email + password) — `login_screen.dart`
- Two roles: **user** (visually impaired person) and **guardian** (caregiver)
- Role stored in MongoDB via `POST /api/auth/register`; retrieved via `GET /api/auth/me`
- Firebase ID token verified server-side by `requireAuth` middleware
- Guardian dashboard receives real-time location + SOS via Socket.IO

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                Flutter Mobile App                   │
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
│   Global VoiceService (speech_to_text + flutter_tts)│
│   Riverpod State Management                         │
│   Hive On-Device Face Storage                       │
└───────────────────────┬─────────────────────────────┘
                        │ HTTP REST + WebSocket (Socket.IO)
          ┌─────────────┴──────────────┐
          │     Node.js Backend        │
          │  Express + Socket.IO       │
          │  Firebase Admin SDK        │
          │  MongoDB via Mongoose      │
          └────────────────────────────┘
```

---

## Project Structure

```
CogniVision/
├── backend/                          # Node.js backend server
│   └── src/
│       ├── config/
│       │   ├── db.js                 # MongoDB/Mongoose connection
│       │   └── firebase.js           # Firebase Admin SDK init
│       ├── middleware/
│       │   ├── requireAuth.js        # Firebase ID token verifier
│       │   └── requireRole.js        # Role-based access guard
│       ├── models/
│       │   └── User.js               # Mongoose user schema (firebaseUid, role, email)
│       ├── routes/
│       │   └── auth.js               # POST /register · GET /me
│       └── index.js                  # Express + Socket.IO server entry
│
└── frontend/gemini_live_app/
    ├── assets/models/
    │   ├── yolov8n.tflite            # YOLOv8 nano model (bundled)
    │   └── yolov8n.txt               # COCO class labels
    ├── lib/
    │   ├── main.dart                 # App entry: Firebase, Hive, Riverpod init
    │   ├── firebase_options.dart     # Generated by FlutterFire CLI
    │   └── src/
    │       ├── flutterfire_ai_live_api_demo.dart  # Gemini Live session orchestrator
    │       ├── providers.dart                      # Riverpod global providers
    │       │
    │       ├── face_features/                      # Face recognition module
    │       │   ├── camera_service.dart             # Back camera + ML Kit face detection
    │       │   ├── face_embedding_service.dart     # MobileFaceNet TFLite (download + inference)
    │       │   ├── face_storage_service.dart       # Hive CRUD + cosine similarity matching
    │       │   ├── registered_face.dart            # Hive model (id, name, embedding, timestamp)
    │       │   ├── registered_face.g.dart          # Generated Hive adapter
    │       │   ├── home_screen.dart
    │       │   ├── register_screen.dart
    │       │   ├── recognize_screen.dart           # Auto-scan loop (300 ms)
    │       │   └── registered_faces_screen.dart
    │       │
    │       ├── gps_core/                           # GPS plumbing
    │       │   ├── navigation_service.dart         # Directions API + turn-by-turn logic
    │       │   ├── command_router.dart             # Voice → navigation command mapping
    │       │   └── socket_service.dart             # Socket.IO singleton (location + SOS)
    │       │
    │       ├── gps_features/user/
    │       │   ├── user_home_screen.dart           # Google Maps UI + navigation controls
    │       │   └── user_provider.dart              # Riverpod RouteState / AppMode
    │       │
    │       ├── services/
    │       │   ├── global_voice_service.dart       # STT singleton + tab-switch commands
    │       │   ├── tts_service.dart                # flutter_tts wrapper
    │       │   └── api_service.dart                # HTTP client for backend auth
    │       │
    │       ├── utilities/
    │       │   ├── yolo_detector.dart              # YOLOv8n TFLite: preprocess → infer → NMS
    │       │   ├── audio_input.dart                # PCM mic capture stream for Gemini
    │       │   ├── audio_output.dart               # SoLoud PCM playback for Gemini responses
    │       │   └── video_input.dart                # Camera → JPEG stream for Gemini
    │       │
    │       ├── screens/
    │       │   ├── main_navigation_wrapper.dart    # Bottom nav bar + mic FAB
    │       │   ├── login_screen.dart               # Firebase email/password auth
    │       │   ├── guardian_screen.dart            # Guardian real-time location view
    │       │   └── placeholder_screens.dart
    │       │
    │       └── ui_components/                      # Shared widgets
    │           ├── bottom_bar.dart
    │           ├── branding.dart
    │           ├── camera_previews.dart
    │           ├── luxury_background.dart
    │           ├── sound_waves.dart
    │           ├── theme.dart
    │           ├── vertical_switch.dart
    │           └── ui_components.dart              # Barrel export
    │
    ├── pubspec.yaml
    └── firebase.json
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | ≥ 3.4.0 |
| Dart SDK | ≥ 3.4.0 |
| Node.js | ≥ 18.x |
| MongoDB | Local or Atlas cluster |
| Firebase project | Auth + Vertex AI in Firebase enabled |
| Google Cloud | Maps SDK for Android/iOS + Directions API enabled |

---

## Setup & Installation

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/cognivision.git
cd cognivision
```

### 2. Flutter App Setup

```bash
cd frontend/gemini_live_app
flutter pub get

# Generate Hive type adapters (re-run if registered_face.dart changes)
dart run build_runner build --delete-conflicting-outputs
```

The **YOLOv8n model** must be placed manually before building:

```
assets/models/yolov8n.tflite
assets/models/yolov8n.txt
```

Download the official nano model from [Ultralytics](https://github.com/ultralytics/ultralytics) and export it to TFLite format.

The **MobileFaceNet model** (~2 MB) is downloaded automatically from GitHub on the first launch of the Face tab.

### 3. Backend Setup

```bash
cd backend
npm install
```

Create `backend/.env`:

```env
PORT=3000
MONGO_URI=mongodb://localhost:27017/cognivision
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_CLIENT_EMAIL=your-service-account@your-project.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

> Get the service account credentials from **Firebase Console → Project Settings → Service Accounts → Generate new private key**.

Start the server:

```bash
npm start
# Server running on port 3000
```

### 4. Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable **Authentication → Email/Password**
3. Enable **Vertex AI in Firebase** (required for Gemini Live API)
4. Run FlutterFire CLI to regenerate `firebase_options.dart`:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

5. Place `google-services.json` in `android/app/` and `GoogleService-Info.plist` in `ios/Runner/`.

### 5. Environment Variables (Flutter)

Create `.env` in `frontend/gemini_live_app/` (next to `pubspec.yaml`):

```env
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
```

Update the hardcoded backend IP in the Flutter source:

```dart
// lib/src/services/api_service.dart
static const String baseUrl = 'http://YOUR_SERVER_IP:3000/api';

// lib/src/gps_core/socket_service.dart
socket = IO.io('http://YOUR_SERVER_IP:3000', ...);
```

---

## Running the App

```bash
# Physical device required — camera/mic/GPS don't work in emulator
flutter run

# Verbose logging (useful for Gemini session debugging)
flutter run -v
```

### Android permissions (`AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS permissions (`Info.plist`)

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
| `GET` | `/health` | None | Liveness check |
| `POST` | `/api/auth/register` | None | Register new user with role |
| `GET` | `/api/auth/me` | Bearer token | Get authenticated user profile |

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
| `firebase_ai ^2.2.0` | Gemini 2.0 Live API (Vertex AI in Firebase) |
| `firebase_auth ^5.5.0` | Email/password authentication |
| `firebase_core ^3.10.1` | Firebase core initialisation |
| `flutter_riverpod ^2.6.1` | Reactive state management |
| `tflite_flutter ^0.12.1` | On-device TFLite inference (YOLOv8n + MobileFaceNet) |
| `google_mlkit_face_detection ^0.10.0` | On-device face bounding box detection |
| `hive ^2.2.3` / `hive_flutter ^1.1.0` | On-device face embedding persistence |
| `record ^6.0.0` | PCM microphone stream for Gemini |
| `flutter_soloud ^3.2.2` | Low-latency PCM audio playback for Gemini responses |
| `speech_to_text ^7.3.0` | Voice command recognition (STT) |
| `flutter_tts ^4.0.2` | Text-to-speech for navigation + YOLO announcements |
| `google_maps_flutter ^2.14.0` | Map display and route polyline |
| `geolocator ^14.0.2` | Real-time GPS position stream |
| `flutter_polyline_points ^3.1.0` | Decodes Google Directions polyline |
| `socket_io_client ^3.1.4` | Real-time location and SOS with backend |
| `camera ^0.11.0+2` | Camera stream for Gemini and YOLO |
| `flutter_dotenv ^6.0.1` | `.env` file at runtime |
| `image ^4.2.0` | JPEG decode + resize for YOLO preprocessing |
| `html ^0.15.6` | Strips HTML tags from Google Directions instructions |

---

## Known Issues & Notes

- **MobileFaceNet model** (~2 MB) is downloaded on first Face tab launch. Ensure internet on first run.
- **YOLOv8n assets** must be manually placed in `assets/models/` before building — not auto-downloaded.
- **Backend IP** in `api_service.dart` and `socket_service.dart` is hardcoded to a local network IP (`10.70.4.162`). Replace with your server URL before deploying.
- **Gemini Live API** (`gemini-2.0-flash-exp`) requires Vertex AI enabled in Firebase and may incur Google Cloud costs.
- **Google Maps API key** must have Maps SDK for Android/iOS and Directions API enabled.
- **Physical device required** — camera, microphone, and GPS do not function in emulators.
- **STT** (`speech_to_text`) may require internet on Android unless the on-device language pack is installed.
- **Socket.IO** is not included in the backend `package.json` by default — add `socket.io` as a dependency if the package.json has not been updated.

---

## Future Enhancements

1. **Cloud face backup** — `FaceStorageService` (`lib/src/face_features/face_storage_service.dart`) is isolated behind a clean interface; swapping Hive for Firestore/S3 requires changes only in this one file.

2. **Multi-language TTS/STT** — `VoiceService` and `TtsService` are decoupled via a listener pattern; locale parameterisation requires changes only in `global_voice_service.dart` and `tts_service.dart`.

3. **Depth-based obstacle distance** — `YoloDetector` already returns normalised bounding boxes; a MiDaS TFLite model can be added alongside the existing pipeline consuming the same JPEG stream from `video_input.dart`.

4. **SOS event history** — The Socket.IO relay and Mongoose `User` model are in place; adding an `SosEvent` schema and REST endpoint requires only a new model and route file on the backend.

5. **Wearable / IoT integration** — `backend/core/location_service/location_service.ino` (Arduino sketch in the repo) demonstrates embedded hardware intent; the Socket.IO server already handles `LOCATION_UPDATE` from any authenticated client, so a wearable integrates without server changes.

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit: `git commit -m "feat: describe your change"`
4. Push: `git push origin feature/your-feature`
5. Open a Pull Request

Run `flutter analyze` and `flutter test` before submitting.

---

*Built with Flutter · Powered by Google Gemini · Designed for accessibility*
