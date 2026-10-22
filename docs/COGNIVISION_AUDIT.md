# CogniVision — Technical Audit & Implementation Readiness Report

**Date of Audit:** October 21, 2026  
**Auditor:** Senior Software Architect, Mobile Engineer (Flutter), ML/CV Engineer & Backend Reviewer  
**Target Repository:** `d:\BattleStation\Projects\CogniVision`  
**Git Branch / Commit:** `main` (latest commit `336f8c2` Merge pull request #1 from Anudeep2005/webapp)  
**Operating Rules Observed:** Read-only inspection; zero destructive changes; no packages installed; secrets redacted.

---

## 1. Executive Summary

CogniVision is conceived as a multimodal assistive technology platform designed for visually impaired users. According to its conceptual design and resume claims, the system consists of:
1. A **Flutter mobile application** performing local on-device YOLOv8 obstacle detection, turn-by-turn walking navigation, face recognition, and Gemini Live bidirectional streaming.
2. A **Node.js/Express backend** managing user authentication, role-based access control, and real-time Socket.IO telemetry relay.
3. A **React web dashboard** for caregivers/guardians to monitor the visually impaired user's live location and activity in real time.

### Current Implementation State & Readiness Verdict
The repository currently represents an **early-stage, partially merged prototype** containing significant architectural fragmentation, broken build pipelines, missing model assets, and disconnected data transports across its subprojects.

| Subproject / Component | Implementation Status | Build / Run State | Critical Finding |
|---|---|---|---|
| **Flutter Mobile App** (`frontend/gemini_live_app`) | Partial / Broken | **Fails to compile & build** | Missing `yolov8n.tflite` model asset causes asset bundler crash; 3 compilation errors in `yolo_detector.dart` (`debugPrint` undefined); unhandled crash on startup if `.env` is absent; unreferenced auth screens. |
| **YOLOv8n / TFLite Pipeline** | Partial / Non-functional | **Inference cannot run** | **Zero model files exist in the repository.** Output post-processing and bounding box math exist in code, but no weights or `.tflite` binaries are present. |
| **Gemini Live / Vertex AI** | Partial / Unverified | **Untested in runtime** | Implemented using `firebase_ai` (`gemini-2.0-flash-exp`), not raw Vertex AI or `gemini-2.5-flash`. Hardcoded 1 FPS image throttle; requires live Firebase credentials. |
| **Node.js / Express Backend** (`backend`) | Partial | **Unrunnable without `npm install`** | `node_modules` not installed; lacks custom JWT issuance (delegates ID token verification to Firebase Admin SDK); location updates are in-memory transient Socket.IO events with no DB persistence. |
| **React Web Dashboard** (`frontend/webapp`) | Partial / Disconnected | **Unrunnable without `npm install`** | `node_modules` not installed; **zero connection to Node.js backend or Socket.IO**; listens only to Firebase Realtime Database at `tracking/currentUser`. |
| **Embedded IoT Tracker** (`location_service.ino`) | Prototype | **Independent hardware script** | ESP32 Arduino sketch pushing GPS coordinates via HTTP PUT directly to Firebase RTDB; contains hardcoded plaintext WiFi credentials. |

### Top 4 Critical Blockers
1. **Missing Model Weights:** Neither `yolov8n.tflite` nor any other object detection model file exists anywhere in the repository.
2. **Flutter Build & Compilation Breakage:** `flutter analyze` reports compile errors (`debugPrint` undefined in `yolo_detector.dart`) and asset bundle errors (`assets/models/yolov8n.tflite` does not exist), preventing `flutter test` and `flutter run` from executing.
3. **Architectural Triangulation Failure:** The three main subprojects communicate over mutually incompatible protocols: the Flutter app emits Socket.IO events to Node.js; the Node.js backend does not store or forward coordinates to Firebase RTDB; and the React dashboard reads exclusively from Firebase RTDB.
4. **Uninstalled Dependencies & Missing Configurations:** Neither `backend` nor `frontend/webapp` has `node_modules` installed. No `.env` or `.env.example` templates exist, causing runtime crashes upon startup.

---

## 2. Repository Structure & Technology Inventory

### 2.1 Compact Directory Tree

```
CogniVision/
├── .git/
├── .gitignore
├── .vscode/
│   └── settings.json
├── README.md
├── backend/
│   ├── core/
│   │   └── location_service/
│   │       └── location_service.ino       # ESP32 GPS-to-Firebase RTDB sketch
│   ├── package.json                       # Express, Socket.IO, Mongoose, Firebase Admin
│   ├── package-lock.json
│   ├── src/
│   │   ├── index.js                       # Express + Socket.IO entry point
│   │   ├── config/
│   │   │   ├── db.js                      # Mongoose connection
│   │   │   └── firebase.js                # Firebase Admin SDK initialization
│   │   ├── middleware/
│   │   │   ├── requireAuth.js             # Firebase ID token verifier
│   │   │   └── requireRole.js             # Role guard (user vs guardian)
│   │   ├── models/
│   │   │   └── User.js                    # Mongoose User schema
│   │   └── routes/
│   │       └── auth.js                    # POST /register, GET /me
│   └── tests/
│       └── auth.test.js                   # Jest unit tests for auth routes
└── frontend/
    ├── gemini_live_app/                   # Flutter Mobile App
    │   ├── analysis_options.yaml
    │   ├── pubspec.yaml                   # Flutter dependencies & asset declarations
    │   ├── pubspec.lock
    │   ├── firebase.json
    │   ├── android/
    │   │   ├── app/
    │   │   │   ├── build.gradle.kts       # Android build config (minSdk 24, NDK 27)
    │   │   │   ├── google-services.json   # Android Firebase client config
    │   │   │   └── src/main/AndroidManifest.xml
    │   ├── ios/
    │   │   ├── Runner/
    │   │   │   ├── AppDelegate.swift
    │   │   │   └── (Info.plist MISSING)
    │   ├── assets/
    │   │   └── models/
    │   │       ├── yolov8n.txt            # 80 COCO class labels
    │   │       └── (yolov8n.tflite MISSING)
    │   ├── lib/
    │   │   ├── main.dart                  # App bootstrap (dotenv, Firebase, Hive)
    │   │   ├── firebase_options.dart      # FlutterFire client options
    │   │   ├── core/location/location.ino # Duplicate Arduino sketch
    │   │   └── src/
    │   │       ├── flutterfire_ai_live_api_demo.dart # Gemini Live & YOLO UI
    │   │       ├── providers.dart         # Riverpod providers
    │   │       ├── face_features/         # Face embedding, storage & screens
    │   │       ├── gps_core/              # NavigationService, SocketService, CommandRouter
    │   │       ├── gps_features/user/     # UserHomeScreen (Google Maps UI)
    │   │       ├── screens/               # LoginScreen, GuardianScreen, Wrapper
    │   │       ├── services/              # GlobalVoiceService, TtsService, ApiService
    │   │       ├── ui_components/         # LuxuryBackground, BottomBar, Branding
    │   │       └── utilities/             # YoloDetector, AudioInput, AudioOutput, VideoInput
    │   └── test/
    │       └── widget_test.dart           # Unit tests (YOLO bbox math, Cosine similarity)
    └── webapp/                            # React Web Application
        ├── package.json                   # React 19, Vite 8, Leaflet, Firebase SDK
        ├── package-lock.json
        ├── index.html
        ├── vite.config.js
        └── src/
            ├── main.jsx                   # React root mount
            ├── App.jsx                    # React Router definition
            ├── pages/
            │   └── Dashboard.jsx          # Live telemetry map view
            ├── hooks/
            │   └── useLiveLocation.js     # Firebase RTDB listener
            ├── components/
            │   ├── MapView.jsx            # Leaflet map container
            │   ├── LocationCard.jsx       # Coordinates & status overlay
            │   ├── Navbar.jsx             # Top branding & connection dot
            │   └── Loader.jsx
            └── services/
                └── firebase.js            # Firebase App & RTDB initialization
```

### 2.2 Subproject Inventory Table

| Subproject | Directory | Language / Framework | Runtime Requirements | Manifest / Lockfile | Startup Commands | Current Configuration |
|---|---|---|---|---|---|---|
| **Mobile App** | `frontend/gemini_live_app` | Dart 3.13+ / Flutter 3.35+ | Flutter SDK ≥ 3.4.0, Android SDK min 24 | `pubspec.yaml`, `pubspec.lock` | `flutter run` | Requires `.env` with `GOOGLE_MAPS_API_KEY` & `yolov8n.tflite` in `assets/models/`. |
| **Backend API** | `backend` | JavaScript / Node.js (Express 4.22) | Node.js ≥ 18.x, MongoDB instance | `package.json`, `package-lock.json` | `npm start` or `npm run dev` | Requires `.env` with `PORT`, `MONGO_URI`, and Firebase Admin private keys. |
| **Web Dashboard** | `frontend/webapp` | JavaScript / React 19, Vite 8 | Node.js ≥ 18.x, npm | `package.json`, `package-lock.json` | `npm run dev` | Requires `.env` with `VITE_FIREBASE_*` credentials. |
| **Hardware Node** | `backend/core/location_service` | C++ / Arduino (ESP32) | Arduino IDE / ESP32 Core, TinyGPS++ | `location_service.ino` | Flashed to ESP32 board | Hardcoded WiFi credentials and Firebase RTDB project URL. |

### 2.3 Tooling, CI/CD, Containerization & Testing
- **CI/CD:** **None.** No `.github/workflows`, GitLab CI, or automation pipelines exist.
- **Docker / Containers:** **None.** No `Dockerfile` or `docker-compose.yml` present in any directory.
- **Environment Templates:** **None.** No `.env.example` exists in root, mobile, webapp, or backend.
- **Automated Tests:**
  - Flutter: `frontend/gemini_live_app/test/widget_test.dart` (Fails to run due to missing asset bundle).
  - Backend: `backend/tests/auth.test.js` (Cannot run due to uninstalled `node_modules`).
  - Web Dashboard: No test files exist (`package.json` contains only `oxlint` lint script).

---

## 3. Flutter Mobile App Audit

### 3.1 Buildability & Main Entry Point
- **Main Entry Point:** `lib/main.dart` (lines 12–21).
- **Execution Flow:**
  1. `WidgetsFlutterBinding.ensureInitialized()`
  2. `await dotenv.load(fileName: ".env")` → **CRITICAL RUNTIME CRASH:** If `.env` is absent on disk, this throws `File not found: .env` and halts execution.
  3. `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
  4. `await Hive.initFlutter(); Hive.registerAdapter(RegisteredFaceAdapter()); await Hive.openBox<RegisteredFace>('faces')`
  5. `runApp(const ProviderScope(child: MyApp()))` launching `MainNavigationWrapper`.
- **Buildability Verdict:** **FAILS TO BUILD.**
  - `flutter analyze` exits with error code 1:
    - 3 compiler errors in `lib/src/utilities/yolo_detector.dart` (lines 39, 41, 135: `The method 'debugPrint' isn't defined for the type 'YoloDetector'`).
    - 2 asset warnings: `assets/models/yolov8n.tflite` and `.env` declared in `pubspec.yaml` do not exist.
  - `flutter test` exits with code 1:
    ```
    Error detected in pubspec.yaml:
    No file or variants found for asset: assets/models/yolov8n.tflite.
    Error: Failed to build asset bundle
    ```

### 3.2 Screens, Navigation & Architecture
- **Active Navigation:** `lib/src/screens/main_navigation_wrapper.dart` uses an `IndexedStack` switching between 3 tabs:
  - Tab 0: `FlutterFireAILiveAPIDemo` (`lib/src/flutterfire_ai_live_api_demo.dart`) — Gemini Live session & YOLO toggle.
  - Tab 1: `UserHomeScreen` (`lib/src/gps_features/user/user_home_screen.dart`) — Google Maps navigation UI.
  - Tab 2: `HomeScreen` (`lib/src/face_features/home_screen.dart`) — MobileFaceNet face detection & recognition.
- **State Management:** Riverpod (`flutter_riverpod ^2.6.1`). Key providers defined in `lib/src/providers.dart`:
  - `audioInputProvider`, `audioOutputProvider`, `videoInputProvider`, `vertexActiveProvider`.
- **Orphaned / Unreferenced Screens:**
  - `LoginScreen` (`lib/src/screens/login_screen.dart`): Implements email/password Firebase Auth and calls `_apiService.register`, but is **never instantiated or routed to** anywhere in the application. Users are never presented with a login or registration screen.
  - `GuardianScreen` (`lib/src/screens/guardian_screen.dart`): Static view with a "Navigate to User" button that only opens Google Maps in a browser; never routed to.
  - `PlaceholderScreens` (`lib/src/screens/placeholder_screens.dart`): Contains mock `GpsNavScreen` and `FaceRecognitionScreen` with "Coming Soon..." banners.

### 3.3 Camera, Audio & Voice Subsystems
- **Camera Capture (`VideoInput` in `lib/src/utilities/video_input.dart`):**
  - Uses `camera: ^0.11.0+2`. Configured for `ResolutionPreset.low` and `ImageFormatGroup.yuv420` (line 27–29).
  - Starts image stream via `startImageStream`.
  - **Severe Performance Bottleneck:** Lines 62–64 throttle frames to 1 FPS (`now - _lastFrameTime < 1000`).
  - Lines 85–119: Converts YUV420 to RGB using a **pure Dart nested loop on the main UI isolate**, then executes `img.encodeJpg(imgBuffer, quality: 60)`. On physical mobile hardware, this blocks the UI thread for 100–300 ms per frame.
- **Microphone & Audio Stream (`AudioInput` & `AudioOutput`):**
  - Input: `record: ^6.0.0` captures 16 kHz 16-bit mono PCM stream (`AudioEncoder.pcm16bits`, lines 7–17 of `audio_input.dart`).
  - Output: `flutter_soloud: ^3.2.2` creates a ring buffer stream at 24 kHz mono (`setupNewStream` in `audio_output.dart`), consuming PCM chunks received from Gemini.
  - Global Voice Service: `speech_to_text: ^7.3.0` and `flutter_tts: ^4.0.2` in `lib/src/services/global_voice_service.dart`. Arbitration logic properly shuts down global voice recognition when entering Tab 0 (Gemini Live) to prevent microphone device locks (`main_navigation_wrapper.dart` lines 50–69).

### 3.4 YOLOv8 / TFLite Integration Details
- **Implementation:** `lib/src/utilities/yolo_detector.dart`.
- **Inference Location:** Designed to run **locally on-device** via `tflite_flutter: ^0.12.1`.
- **Model Asset Check:** `Interpreter.fromAsset('assets/models/yolov8n.tflite')` (line 35). **Asset does not exist.**
- **Label File:** `assets/models/yolov8n.txt` exists and contains 80 standard COCO lines.
- **Preprocessing:** Takes JPEG bytes, decodes them via `img.decodeImage` (CPU), resizes to 640×640 via `img.copyResize`, and iterates over 409,600 pixels to populate a flat `Float32List(1 * 640 * 640 * 3)` normalized to `[0.0, 1.0]`.
- **Tensor Input:** `[1, 640, 640, 3]` Float32.
- **Tensor Output:** `[1, 84, 8400]` Float32.
- **Output Parsing & NMS:**
  - Decodes 8400 anchor predictions: 4 bbox coordinates (`[cx, cy, w, h]`) and 80 class scores.
  - Confidence threshold: `0.45` (line 97).
  - Greedy Non-Maximum Suppression: IoU threshold `0.45`, max 5 detections (lines 113–131).
- **TTS Announcement:** `TtsService.announceDetections` (`lib/src/services/tts_service.dart`) determines relative direction based on bounding box horizontal center (`cx < 0.33` → "on the left", `cx > 0.66` → "on the right", else "ahead") and announces up to 3 objects.
- **UI Overlay:** `YoloPainter` (`lib/src/flutterfire_ai_live_api_demo.dart` lines 619–649) paints bounding boxes and labels onto `CameraPreview`.

### 3.5 Permissions & Native Platform Configuration
- **Android (`android/app/src/main/AndroidManifest.xml`):**
  - `INTERNET`, `RECORD_AUDIO`, `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.
  - Android Gradle (`android/app/build.gradle.kts`): Kotlin DSL, `minSdk = 24`, `targetSdk = flutter.targetSdkVersion`, `compileSdk = flutter.compileSdkVersion`, NDK `27.0.12077973`.
  - Reads `GOOGLE_MAPS_API_KEY` from `local.properties` or fallback `.env`.
- **iOS (`frontend/gemini_live_app/ios/`):**
  - **`Info.plist` is missing from `ios/Runner/`.** iOS builds cannot declare `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, or `NSLocationWhenInUseUsageDescription` until this file is restored.

---

## 4. YOLOv8n / TFLite Model Audit

### 4.1 Artifact Inventory & Verification Status
| Attribute | Verified Code Expectation | Actual Repository State | Status |
|---|---|---|---|
| **Model File** | `assets/models/yolov8n.tflite` | File does not exist anywhere in repo | **MISSING** |
| **Weights Format** | TFLite FlatBuffer (`.tflite`) | No `.pt`, `.onnx`, or `.tflite` present | **MISSING** |
| **Model Variant** | YOLOv8 nano (COCO-pretrained) | Claimed in comments, unverified | **UNVERIFIED** |
| **Class Labels** | `assets/models/yolov8n.txt` | 80 classes matching standard COCO | **PRESENT** |
| **Input Shape** | `[1, 640, 640, 3]` | Configured in `yolo_detector.dart:56` | **HARDCODED** |
| **Input Datatype** | Float32, RGB, normalized [0, 1] | Configured in `yolo_detector.dart:62-64` | **HARDCODED** |
| **Output Shape** | `[1, 84, 8400]` | Configured in `yolo_detector.dart:70` | **HARDCODED** |
| **Output Datatype** | Float32 | Configured in `yolo_detector.dart:70` | **HARDCODED** |
| **Hardware Delegates** | None (CPU only) | No `GpuDelegate` or `NnApiDelegate` configured | **SUB-OPTIMAL** |

### 4.2 Architectural Risks & Decoding Incompatibilities
1. **Ultralytics Export Dimension Trap:** When exporting YOLOv8 using `yolo export model=yolov8n.pt format=tflite`, the default export format may output transposed tensors (`[1, 8400, 84]`) or int8-quantized tensors unless explicitly configured. If an exported `.tflite` model produces `[1, 8400, 84]`, the hardcoded stride indexing `(4 + j) * 8400 + i` in `yolo_detector.dart:90` will read corrupted indices and crash `Interpreter.run`.
2. **Main-Thread Latency:**
   - Frame capture: Camera YUV420 → JPEG encoding in Dart (`~150 ms`).
   - Frame preprocessing: JPEG decoding in Dart (`~100 ms`) → Resize to 640×640 (`~80 ms`) → Float32 array conversion (`~60 ms`).
   - CPU Inference on mobile: 640×640 Float32 on mobile CPU without GPU/NNAPI delegate takes approximately **200–450 ms**.
   - Total latency: **500–800 ms per frame**, freezing the Flutter UI isolate if executed on the main thread.
3. **No Direct PyTorch (.pt) Support:** A `.pt` model file cannot be loaded by Flutter or `tflite_flutter`.

### 4.3 Lowest-Risk Approach to Working On-Device Inference
1. Export official `yolov8n.pt` using Ultralytics to Float32 TFLite:
   ```bash
   yolo export model=yolov8n.pt format=tflite imgsz=640
   ```
2. Verify input tensor is `[1, 640, 640, 3]` (Float32) and output tensor matches `[1, 84, 8400]` (or adjust `yolo_detector.dart` index math to match `[1, 8400, 84]`).
3. Place `yolov8n.tflite` into `frontend/gemini_live_app/assets/models/yolov8n.tflite`.
4. Add `import 'package:flutter/foundation.dart';` to `yolo_detector.dart` to resolve `debugPrint` compilation errors.
5. Move inference and preprocessing off the UI isolate into a Dart background worker (`Isolate.run` or `compute`).

---

## 5. Gemini Live / Vertex AI Audit

### 5.1 Architecture & SDK Usage
- **Integration Layer:** Uses `firebase_ai: ^2.2.0` (`FirebaseAI.vertexAI().liveGenerativeModel(...)`).
- **Does NOT use direct Google Cloud Vertex AI REST/gRPC SDK or custom WebSocket client.** It relies entirely on the Firebase Vertex AI Live API client library.
- **Model Identifier:** `gemini-2.0-flash-exp` (`lib/src/flutterfire_ai_live_api_demo.dart` line 28).
  - *Contrast with Resume Claim A:* Resume claims "Gemini Live 2.5 Flash Native Audio". The codebase contains `gemini-2.0-flash-exp`. No reference to `2.5` or `gemini-2.5-flash` exists.

### 5.2 Streaming Implementation Details
- **Bidirectional Streaming:** **Implemented in code.**
  - `_session = await _liveModel.connect()` creates a bidirectional `LiveSession`.
  - Media stream: `_combinedMediaController = StreamController<InlineDataPart>()` fed into `_session.sendMediaStream(...)` (lines 166–168).
  - Audio input: 16 kHz PCM audio chunks from `record` wrapped as `InlineDataPart('audio/pcm;rate=16000', data)` (line 175).
  - Video stream: Camera JPEG frames wrapped as `InlineDataPart('image/jpeg', image)` (line 227).
  - Incoming stream: `_session.receive()` listened to in `processMessagesContinuously()` (lines 337–348).
  - Incoming audio: `InlineDataPart` with mimeType starting with `audio` passed to `AudioOutput.addDataToAudioStream` for SoLoud playback (lines 391–395).
- **Frame Rate & Latency:**
  - Video streaming is hard-throttled to **1 FPS (1000 ms)** in `video_input.dart:62`.
  - Video and audio are multiplexed into a single stream controller.
- **Session Lifecycle & Fault Tolerance:**
  - Watchdog timer: Checks every 10 seconds. If `DateTime.now().difference(_lastModelResponse).inSeconds > 25`, it triggers a restart of audio/video streams (lines 308–320).
  - Interruption handling: Detects `response.interrupted` flag (line 362), but currently only logs it (`log('Interrupted: $response')`) without flushing the SoLoud audio buffer.
- **Credentials & Security:**
  - No Vertex AI service account private keys are embedded in client code.
  - The client authenticates against Firebase Vertex AI using standard App Check / Firebase project initialization (`google-services.json` on Android, `firebase_options.dart`).

---

## 6. React Dashboard Audit

### 6.1 Framework & Build Tool
- **Framework:** React 19.2.7, Vite 8.1.1, React Router DOM 7.18.1 (`frontend/webapp/package.json`).
- **State Management:** Local React hooks (`useState`, `useEffect`) and custom hook `useLiveLocation`.

### 6.2 Pages, Routing & Components
- Single routed page: `Dashboard` (`src/pages/Dashboard.jsx`) mounted at `/` (`src/App.jsx`).
- Components:
  - `MapView.jsx`: Renders full-screen map via `react-leaflet: ^5.0.0` and `leaflet: ^1.9.4` using OpenStreetMap tile layers. Features custom pulsing radar SVG marker (`pulseIcon`, lines 8–14) and auto-pan/fly controller (`MapController`, lines 17–49).
  - `LocationCard.jsx`: Glassmorphic HUD overlay displaying latitude, longitude, connection status, live clock, relative timestamp counter, and recenter button.
  - `Navbar.jsx`: Brand title with pulsing green/orange Firebase connection indicator dot.
  - `Loader.jsx`: Animated glassmorphic loading spinner.

### 6.3 Authentication & Backend Integration Status
- **Authentication:** **Completely absent.** There is no login screen, no token management, no caregiver identity, and no route protection.
- **Backend API Integration:** **Completely absent.** The React app makes **zero HTTP requests to the Node.js backend** and **zero WebSocket/Socket.IO connections**.
- **Data Source:** Connects directly to **Firebase Realtime Database** via Firebase Web SDK v12 (`src/services/firebase.js`).
  - Listens to `tracking/currentUser` via `onValue(locationRef, ...)` (`src/hooks/useLiveLocation.js:32-53`).
  - Monitors connection status at `.info/connected`.
- **Mock vs. Real Data:**
  - If Firebase RTDB is empty or unconfigured, it displays fallback hardcoded coordinates `[17.432141, 78.341221]` (Hyderabad coordinates) and renders an error card.
  - It does not receive live location from the Flutter mobile app because the Flutter mobile app sends location to the Node.js backend via Socket.IO, not to Firebase RTDB.

---

## 7. Node.js / Express Backend Audit

### 7.1 Runtime, Framework & Entry Point
- **Runtime:** Node.js (tested against Node v24.22.0).
- **Framework:** Express 4.22.1 with `http.createServer` and `socket.io: ^4.7.5`.
- **Entry Point:** `backend/src/index.js`.
- **Database:** MongoDB via `mongoose: ^9.6.2`.

### 7.2 API Endpoints & Routes
- `GET /health` (`src/index.js:28`): Unauthenticated health check returning `{ status: 'ok' }`.
- `POST /api/auth/register` (`src/routes/auth.js:7`):
  - Accepts `{ firebaseUid, role, displayName, email }`.
  - Validates `role` must be `'user'` or `'guardian'`.
  - Checks if user already exists by `firebaseUid`.
  - Persists new `User` document in MongoDB.
- `GET /api/auth/me` (`src/routes/auth.js:37`):
  - Protected by `requireAuth` middleware.
  - Returns `req.dbUser`.

### 7.3 Authentication & JWT Reality Check
- **JWT Issuance:** **The backend does not issue JWT tokens.**
  - There is no `jsonwebtoken` package in `package.json`.
  - No secret signing keys, token expiration configs, or refresh token mechanisms exist.
- **Token Verification:**
  - `requireAuth` middleware (`src/middleware/requireAuth.js:18`) extracts `Bearer <token>` from the HTTP `Authorization` header and delegates verification to Firebase Admin SDK:
    `admin.auth().verifyIdToken(idToken)`.
  - Resolves `decodedToken.uid`, then queries MongoDB for `User.findOne({ firebaseUid })`.

### 7.4 Real-time Telemetry & Ingestion Gaps
- **Socket.IO Relays (`src/index.js:49-76`):**
  - Event `join`: Client joins room `userId`.
  - Event `LOCATION_UPDATE`: Server relays payload `{ userId, lat, lng, timestamp }` to room `userId` via `socket.to(userId).emit('LOCATION_UPDATE', data)`.
  - Event `SOS_ALERT`: Server relays payload `{ userId, type: "SOS", status: "active" }` to room `userId`.
- **Persistence Gap:**
  - **Location and SOS data are purely ephemeral in-memory relays.** The backend never writes location updates, breadcrumb histories, or SOS incidents to MongoDB or any database.
- **Integration Disconnect:**
  - The Flutter app connects to Socket.IO with a hardcoded room `'user_123'` (`user_home_screen.dart:36`).
  - The React webapp does not connect to Socket.IO at all.
  - No caregiver-user pairing logic exists in MongoDB schemas or backend APIs.

---

## 8. End-to-End Architecture

### 8.1 Current Architecture (As Implemented in Code)

The following diagram illustrates the actual relationships, protocols, and broken links verified in the codebase.

```mermaid
flowchart TD
    subgraph MobileApp["Flutter Mobile App (gemini_live_app)"]
        UI["MainNavigationWrapper"]
        Cam["VideoInput (Camera Plugin)"]
        Mic["AudioInput (Record Plugin)"]
        AudioOut["AudioOutput (SoLoud Plugin)"]
        GPS["NavigationService (Geolocator)"]
        
        YOLO["YoloDetector (tflite_flutter)\n[BROKEN: Missing yolov8n.tflite]"]
        FaceNet["FaceEmbeddingService\n[Downloads MobileFaceNet from GitHub]"]
        HiveDB[("Hive Local Face DB")]
        
        GeminiClient["FlutterFireAILiveAPIDemo\n(firebase_ai SDK)"]
        SocketClient["SocketService (socket_io_client)\n[Hardcoded: user_123]"]
        FlutterAuth["LoginScreen (Firebase Auth)\n[ORPHANED: Never Shown]"]
    end

    subgraph CloudAI["Google Cloud / Firebase AI"]
        GeminiLive["Firebase Vertex AI Live API\n(model: gemini-2.0-flash-exp)"]
    end

    subgraph BackendServer["Node.js / Express Backend"]
        Express["Express Server (Port 3000)"]
        SocketServer["Socket.IO Relay"]
        FBAdmin["Firebase Admin SDK\n(verifyIdToken)"]
        MongoDB[("MongoDB (User Collection)")]
    end

    subgraph CaregiverWeb["React Web App (webapp)"]
        ViteReact["Dashboard (React 19 / Leaflet)"]
        RTDBHook["useLiveLocation Hook"]
    end

    subgraph FirebaseCloud["Firebase Platform"]
        FBRTDB[("Firebase Realtime Database\npath: tracking/currentUser")]
        FirebaseAuthService["Firebase Auth"]
    end

    subgraph IoTDevice["Embedded Hardware Node"]
        ESP32["location_service.ino\n(TinyGPS++ / WiFi)"]
    end

    %% Verified Connections
    Cam -.->|YUV420 to JPEG 1 FPS| YOLO
    Cam -->|JPEG 1 FPS| GeminiClient
    Mic -->|16kHz PCM| GeminiClient
    GeminiClient <==>|Bidirectional Media Stream| GeminiLive
    GeminiLive -->|24kHz PCM| AudioOut
    FaceNet <-->|Cosine Match| HiveDB
    
    GPS -->|Coordinates| SocketClient
    SocketClient -->|Socket.IO emit LOCATION_UPDATE| SocketServer
    
    ESP32 -->|HTTP PUT lat/lng every 2s| FBRTDB
    FBRTDB -->|onValue listener| RTDBHook
    RTDBHook --> ViteReact

    %% Disconnected / Broken Links
    SocketServer -.->|BROKEN: No listener in webapp| ViteReact
    SocketServer -.->|BROKEN: No persistence| MongoDB
    Express -->|Verify Token| FBAdmin
    Express -->|User Schema| MongoDB
    FlutterAuth -.->|POST /api/auth/register\n(Never triggered)| Express
```

---

### 8.2 Proposed Target Architecture

The following diagram represents the coherent, production-ready architecture required to fulfill the product vision while preserving existing modules.

```mermaid
flowchart TD
    subgraph MobileDevice["Flutter Mobile App (Edge Device)"]
        direction TB
        CameraDriver["Camera Stream (ImageFormatGroup.yuv420)"]
        MicDriver["PCM Microphone Capture (16kHz Mono)"]
        AudioPlayback["PCM Audio Output (SoLoud / 24kHz)"]
        LocalGPS["Geolocator GPS Stream"]
        
        subgraph LocalML["On-Device AI Engine (Zero Network Dependency)"]
            FrameIsolate["Worker Isolate (YUV-to-Float32)"]
            TFLiteRunner["YOLOv8n TFLite Interpreter\n(COCO Pretrained + NNAPI/GPU Delegate)"]
            NMSFilter["NMS & Directional Spatial Filter"]
            LocalTTS["flutter_tts Voice Feedback"]
        end
        
        subgraph CloudAIBridge["Cloud Conversational AI Assistant"]
            GeminiOrchestrator["Gemini Live Session Manager"]
            SessionWatchdog["Heartbeat & Watchdog Auto-Recovery"]
        end
        
        TelemetryService["Telemetry & Socket.IO Client"]
    end

    subgraph BackendInfra["Node.js / Express Telemetry & Auth Gateway"]
        AuthMiddleware["JWT / Firebase Auth Middleware"]
        TelemetryRelay["Socket.IO Secure Namespace Gateway"]
        LocationIngestion["Location & Event Ingestion Controller"]
        DBStore[("MongoDB\n- Users & Roles\n- Caregiver-Patient Links\n- Location Breadcrumbs\n- SOS Incident Logs")]
    end

    subgraph CaregiverPortal["React Caregiver Dashboard"]
        AuthGuard["Caregiver Auth & Token Manager"]
        RealtimeSocket["Socket.IO Client (Subscribed to Patient ID)"]
        MapEngine["Leaflet / MapLibre Live Tracker"]
        AlertsPanel["SOS Alert & Safety Notifications"]
    end

    subgraph CloudServices["Google Cloud Platform"]
        VertexGemini["Vertex AI / Gemini Live 2.0 Flash\nBidirectional Audio-Visual Streaming"]
    end

    %% Data Flows
    CameraDriver -->|Zero-copy Frame| FrameIsolate
    FrameIsolate -->|Float32 Tensor [1, 640, 640, 3]| TFLiteRunner
    TFLiteRunner --> NMSFilter
    NMSFilter -->|Spatial Direction Audio| LocalTTS

    CameraDriver -->|Sampled JPEG Frames (1-2 FPS)| GeminiOrchestrator
    MicDriver -->|16kHz PCM Stream| GeminiOrchestrator
    GeminiOrchestrator <==>|Bidirectional WebSockets / Streaming API| VertexGemini
    VertexGemini -->|Streaming Audio Response| AudioPlayback

    LocalGPS -->|Coordinate & Speed Updates| TelemetryService
    TelemetryService -->|WSS: LOCATION_UPDATE & SOS| TelemetryRelay
    TelemetryRelay --> LocationIngestion
    LocationIngestion --> DBStore
    TelemetryRelay -->|Real-time Room Broadcast| RealtimeSocket
    RealtimeSocket --> MapEngine
    RealtimeSocket --> AlertsPanel
    AuthGuard --> AuthMiddleware
```

---

## 9. Project Actual State & Verification Findings

### 9.1 Environment & Toolchain Status
- **Host OS:** Windows 11 Pro / PowerShell.
- **Flutter SDK:** Flutter 3.47.7 (Channel stable), Framework revision `abaf9c5237`, Engine revision `d8a2d6c768`.
- **Dart SDK:** Dart 3.13.5 (DevTools 2.60.0).
- **Node.js:** v24.22.0.
- **npm:** 11.19.1 (`npm.cmd`).
- **Python:** 3.13.16.
- **Git:** 2.56.0.windows.2.

### 9.2 Verification Commands & Exact Outcomes
| Command Executed | Subproject / Working Directory | Exit Code | Result & Exact Output Snippet |
|---|---|---|---|
| `git status` | Root (`CogniVision`) | 0 | Branch `main`, clean working tree with 2 unstaged tracked modifications: `analysis_options.yaml` and `pubspec.lock`. |
| `flutter analyze` | `frontend/gemini_live_app` | 1 | **51 issues found.** 3 fatal compilation errors in `yolo_detector.dart`: `The method 'debugPrint' isn't defined for the type 'YoloDetector'`. 2 asset warnings: `yolov8n.tflite` and `.env` missing. |
| `flutter test` | `frontend/gemini_live_app` | 1 | **Failed to build asset bundle.** `No file or variants found for asset: assets/models/yolov8n.tflite`. |
| `Test-Path backend/node_modules` | `backend` | 0 | `False`. Dependencies not installed. `npm test` cannot run. |
| `Test-Path webapp/node_modules` | `frontend/webapp` | 0 | `False`. Dependencies not installed. Webapp cannot build. |
| `Get-ChildItem -Filter *.tflite` | Entire repository | 0 | **0 files returned.** No TFLite or PyTorch weights exist anywhere on disk. |

---

## 10. Resume Claim Verification Matrix

This matrix evaluates the specific claims on your resume against concrete repository evidence.

| Resume Claim | Code Evidence Found | Exact File Paths & Line Numbers | Actual Status | Additional Testing Required | Work Needed to Make Claim Demonstrably True |
|---|---|---|---|---|---|
| **Claim A:**<br>"Designed a low-latency pipeline streaming live camera frames to Gemini Live 2.5 Flash Native Audio via Vertex AI, enabling bi-directional audio-visual interaction and real-time scene narration using Streaming APIs." | • `FirebaseAI.vertexAI().liveGenerativeModel` configured with `gemini-2.0-flash-exp` (not 2.5).<br>• Camera frames sent as JPEG via `InlineDataPart`.<br>• Audio input via `record` (16kHz PCM); output via `flutter_soloud` (24kHz PCM).<br>• Frame rate is throttled to 1 FPS via `DateTime` delta. | • `frontend/gemini_live_app/lib/src/flutterfire_ai_live_api_demo.dart:26-42`<br>• `frontend/gemini_live_app/lib/src/flutterfire_ai_live_api_demo.dart:164-185`<br>• `frontend/gemini_live_app/lib/src/flutterfire_ai_live_api_demo.dart:224-236`<br>• `frontend/gemini_live_app/lib/src/utilities/video_input.dart:62` | **PARTIAL & UNVERIFIED** | Live physical device test with valid Firebase project and Vertex AI billing enabled; latency benchmark measuring audio turnaround and video stream stability. | 1. Update model identifier to official 2.0/2.5 flash string supported by Vertex AI.<br>2. Replace slow CPU JPEG loop with native hardware YUV/NV21 encoder.<br>3. Provide valid Firebase options and `.env` configurations.<br>4. Implement user interruption audio-buffer flush. |
| **Claim B:**<br>"Integrated on-device YOLOv8 (COCO-pretrained) for real-time obstacle detection, delivering sub-second inference latency with zero network dependency." | • Code contains full decoding, NMS math, tensor reshape, and TTS spatial feedback.<br>• **Model file `yolov8n.tflite` is completely missing from disk.**<br>• `yolo_detector.dart` fails to compile (`debugPrint` undefined).<br>• Preprocessing executes on main UI isolate with double image conversion. | • `frontend/gemini_live_app/lib/src/utilities/yolo_detector.dart:28-171`<br>• `frontend/gemini_live_app/lib/src/services/tts_service.dart:23-45`<br>• `frontend/gemini_live_app/assets/models/yolov8n.txt:1-80`<br>• `frontend/gemini_live_app/pubspec.yaml:53` | **BROKEN & MISSING ASSET** | End-to-end benchmark on physical Android/iOS hardware measuring frame conversion time, inference time in milliseconds, and NMS execution time. | 1. Export genuine COCO-pretrained `yolov8n.tflite` and commit to `assets/models/`.<br>2. Add `import 'package:flutter/foundation.dart';` to fix compile error.<br>3. Offload frame resize and inference to a background Isolate.<br>4. Verify tensor dimension parity (`[1, 84, 8400]` vs `[1, 8400, 84]`). |
| **Claim C:**<br>"Developed a Node.js/Express.js REST API backend with JWT-based authentication and a React.js web dashboard enabling caregivers to monitor the user's location and activity in real time." | • Express server has `/health`, `POST /api/auth/register`, `GET /api/auth/me`.<br>• **Backend does not issue JWTs** (verifies Firebase ID tokens).<br>• **React dashboard does not connect to Node backend or Socket.IO** (reads Firebase RTDB directly).<br>• No activity monitoring (walking/still/SOS history) exists in dashboard. | • `backend/src/index.js:28-76`<br>• `backend/src/middleware/requireAuth.js:18`<br>• `backend/src/routes/auth.js:7-40`<br>• `frontend/webapp/src/hooks/useLiveLocation.js:32-53`<br>• `frontend/webapp/src/pages/Dashboard.jsx:75-94` | **PARTIAL & DISCONNECTED** | Integration tests simulating Flutter location emissions → Node.js Socket.IO / REST ingestion → React dashboard map rendering; authentication expiration tests. | 1. Implement authentic JWT issuance/verification OR document Firebase ID token auth clearly.<br>2. Connect React dashboard to Node.js backend via Socket.IO.<br>3. Persist location breadcrumbs and activity states in MongoDB.<br>4. Add caregiver login and patient-pairing UI in React dashboard. |

---

## 11. Security and Configuration Findings

> [!WARNING]
> Several critical security risks and credential leaks were detected during the audit. The actual secret values are redacted below per strict operating rules.

1. **Hardcoded Plaintext WiFi Credentials in Embedded Source:**
   - Files: `backend/core/location_service/location_service.ino` (lines 7–8) and `frontend/gemini_live_app/lib/core/location/location.ino` (lines 7–8).
   - Finding: Contains hardcoded WiFi SSID (`ssid`) and plaintext WiFi password (`password`).
   - Remediation: Remove hardcoded credentials; supply network parameters via build flags or runtime provisioning.
2. **Exposed Firebase RTDB Database URLs:**
   - Files: `backend/core/location_service/location_service.ino` (line 11) and `frontend/gemini_live_app/lib/core/location/location.ino` (line 11).
   - Finding: Public Firebase Realtime Database URL hardcoded into C++ source targeting an unauthenticated `/tracking/currentUser.json` endpoint.
   - Remediation: Enforce Firebase RTDB Security Rules and authentication tokens.
3. **Missing Environment Templates (`.env.example`):**
   - No `.env.example` files exist. Developers cannot determine required keys without inspecting code.
   - Required variables discovered in code:
     - Flutter: `GOOGLE_MAPS_API_KEY`, `MAPS_API_KEY`, `BACKEND_URL`.
     - Backend: `PORT`, `MONGO_URI`, `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`.
     - React Webapp: `VITE_FIREBASE_API_KEY`, `VITE_FIREBASE_AUTH_DOMAIN`, `VITE_FIREBASE_DATABASE_URL`, `VITE_FIREBASE_PROJECT_ID`, `VITE_FIREBASE_STORAGE_BUCKET`, `VITE_FIREBASE_MESSAGING_SENDER_ID`, `VITE_FIREBASE_APP_ID`.
4. **Permissive CORS and Socket.IO Origin:**
   - File: `backend/src/index.js` (lines 14, 24).
   - Finding: CORS is open to all origins (`origin: '*'`) across both Express HTTP and Socket.IO servers.
   - Remediation: Restrict allowed origins to verified domains/mobile user-agents.
5. **No Rate Limiting or Brute-Force Protection:**
   - File: `backend/src/routes/auth.js`.
   - Finding: Registration endpoint lacks rate limiting, allowing automated credential spamming.

---

## 12. Prioritized Implementation Roadmap

```
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 0: Baseline Recovery & Buildability                              │
│ (Fix compile errors, restore missing model, add .env templates)        │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 1: Milestone 1 — On-Device YOLOv8n Local Object Detection        │
│ (Camera frame → YOLOv8n TFLite inference → Labels + BBox overlay)      │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 2: ML Performance & Pipeline Optimization                        │
│ (Worker Isolate, GPU/NNAPI delegate, real-time FPS benchmarks)         │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 3: Gemini Live / Vertex AI Streaming Stabilization               │
│ (Model identifier alignment, native PCM playback, session recovery)    │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 4: Node.js Backend & Telemetry Persistence                       │
│ (MongoDB location breadcrumbs, SOS logs, caregiver-patient pairing)   │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 5: React Caregiver Dashboard Real-Time Integration               │
│ (Socket.IO client, patient tracking, SOS notifications, caregiver auth)│
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 6: E2E Verification, CI/CD & Deployment Readiness                │
│ (GitHub Actions, Dockerfiles, unit/integration test coverage)          │
└────────────────────────────────────────────────────────────────────────┘
```

### Phase 0 — Repository Recovery, Setup & Reproducible Baseline
- **Goal:** Fix all compilation errors, provide required baseline assets and environment templates, and make `flutter test` and `npm install` succeed.
- **Prerequisites:** Flutter 3.x, Node.js 18+.
- **Files to Modify/Create:**
  - `frontend/gemini_live_app/lib/src/utilities/yolo_detector.dart`: Add `import 'package:flutter/foundation.dart';`.
  - `frontend/gemini_live_app/assets/models/yolov8n.tflite`: Place verified 640×640 Float32 TFLite model.
  - `frontend/gemini_live_app/.env.example`, `backend/.env.example`, `frontend/webapp/.env.example`: Create documented configuration templates.
  - `frontend/gemini_live_app/lib/main.dart`: Make `dotenv.load` safe against missing `.env` (fallback or warning instead of unhandled crash).
  - `frontend/gemini_live_app/ios/Runner/Info.plist`: Recreate standard iOS permission manifest.
- **Acceptance Criteria:** `flutter analyze` passes with 0 errors; `flutter test` passes unit tests; `npm install` completes cleanly in `backend` and `frontend/webapp`.

### Phase 1 — Milestone 1: On-Device YOLOv8n Inference Pipeline
- **Goal:** Realize `CAMERA FRAME → ON-DEVICE YOLOv8n INFERENCE → DETECTED OBJECT LABELS + CONFIDENCE → VISIBLE OVERLAY / DEBUG OUTPUT` without cloud or backend dependencies.
- **Prerequisites:** Phase 0 complete.
- **Files to Modify:**
  - `frontend/gemini_live_app/lib/src/utilities/yolo_detector.dart`
  - `frontend/gemini_live_app/lib/src/utilities/video_input.dart`
  - `frontend/gemini_live_app/lib/src/flutterfire_ai_live_api_demo.dart`
- **Acceptance Criteria:** App boots into standalone vision mode; back camera renders preview; YOLO detects standard objects (e.g., person, bottle, chair); bounding boxes and labels render on screen in real time.

### Phase 2 — Real-Time ML Performance & Pipeline Optimization
- **Goal:** Eliminate UI frame drops; decouple inference from the UI thread; measure and document inference latency.
- **Prerequisites:** Phase 1 complete.
- **Implementation Tasks:**
  - Convert camera frames directly from YUV420 to RGB/Float32 without intermediate JPEG encode/decode.
  - Execute inference inside a Dart background isolate (`Isolate.run`).
  - Configure `tflite_flutter` with `InterpreterOptions()..addDelegate(GpuDelegateV2())` or `NnApiDelegate()`.
  - Add latency timers logging `preprocess_ms`, `inference_ms`, and `nms_ms`.
- **Acceptance Criteria:** Total pipeline latency < 250 ms on physical Android/iOS hardware; UI maintains steady 60 FPS.

### Phase 3 — Gemini Live / Vertex AI Streaming Stabilization
- **Goal:** Verify and stabilize bidirectional audio/video streaming with Gemini Live.
- **Prerequisites:** Google Cloud / Firebase project with Vertex AI in Firebase enabled.
- **Implementation Tasks:**
  - Audit and update model string to current supported identifier (`gemini-2.0-flash-exp` or target release).
  - Implement buffer flush on user speech interruption (`response.interrupted == true`).
  - Optimize JPEG frame resolution for visual clarity vs. bandwidth.
- **Acceptance Criteria:** Live audio dialogue functions with conversational voice responses played through SoLoud; camera scene queries answered accurately.

### Phase 4 — Node.js Backend & Telemetry Persistence
- **Goal:** Establish reliable authentication and telemetry ingestion.
- **Prerequisites:** Running MongoDB instance.
- **Implementation Tasks:**
  - Add Mongoose `LocationLog` and `SosAlert` schemas.
  - Implement `POST /api/telemetry/location` and persist incoming Socket.IO coordinates.
  - Implement caregiver-to-user pairing relationship in `User` model.
  - Connect mobile `LoginScreen` to backend registration and persist Firebase auth session.
- **Acceptance Criteria:** Backend tests pass; location updates emitted by mobile app persist to MongoDB and can be queried via REST.

### Phase 5 — React Caregiver Dashboard Real-Time Integration
- **Goal:** Connect React dashboard to Node.js backend and display real-time telemetry.
- **Prerequisites:** Phase 4 complete.
- **Implementation Tasks:**
  - Install and configure `socket.io-client` in `frontend/webapp`.
  - Replace Firebase RTDB listener with authenticated Socket.IO connection joining patient room.
  - Add SOS alert toast / modal notification when `SOS_ALERT` event is received.
  - Display battery, activity status, and location history path on Leaflet map.
- **Acceptance Criteria:** Moving the mobile app updates the React map marker within 500 ms without page refresh; triggering SOS on mobile displays audible/visual alert on dashboard.

### Phase 6 — E2E Testing, CI/CD & Deployment Readiness
- **Goal:** Automated testing, containerization, and production deployment packaging.
- **Implementation Tasks:**
  - Create GitHub Actions workflow running `flutter test`, `backend npm test`, and `webapp npm run build`.
  - Create `Dockerfile` and `docker-compose.yml` for Node.js backend and MongoDB.
  - Produce benchmark report documenting latency and memory usage.

---

## 13. Acceptance Criteria for the First YOLOv8n Milestone

To achieve the first milestone without external service dependencies, the implementation must satisfy the following verifiable criteria:

1. **Asset Presence & Validation:**
   - `assets/models/yolov8n.tflite` exists on disk with non-zero file size.
   - Model input matches tensor shape `[1, 640, 640, 3]`, Float32.
   - `assets/models/yolov8n.txt` contains 80 newline-separated class labels.
2. **Compilation & Packaging:**
   - `flutter analyze` runs on `frontend/gemini_live_app` with **0 errors**.
   - `flutter test` completes successfully and passes unit tests in `widget_test.dart`.
3. **Standalone Bootstrapping:**
   - App launches on physical device without requiring network connectivity, Firebase login, or backend server execution.
4. **Live Inference Pipeline Execution:**
   - Back camera stream starts and renders continuous preview.
   - Camera frames are downscaled and fed into `TFLite` interpreter.
   - `detect()` yields valid `DetectionResult` objects when objects are present.
5. **Visible Debug Output / Overlay:**
   - Red bounding box rectangles are drawn over detected objects on the camera view.
   - Label and confidence percentage (e.g. `person 88%`) are visible above each bounding box.
   - Directional TTS announces top detected objects (e.g., "person ahead") without crashing.

---

## 14. Open Questions & Unverified Facts

1. **Original YOLOv8n Model Artifact:** What exact export parameters were intended for the original `yolov8n.tflite` model (Float32 vs. Int8 quantized, shape `[1, 84, 8400]` vs. `[1, 8400, 84]`)?
2. **Target Firebase Project Status:** Does an active Firebase project with Vertex AI in Firebase and Blaze (pay-as-you-go) billing exist for testing Gemini Live?
3. **Caregiver Architecture Decision:** Was the direct Firebase RTDB connection in `webapp` and ESP32 an experimental branch intended to bypass the Node.js backend, or should all telemetry be consolidated under the Node.js / Socket.IO backend?
4. **iOS Deployment Scope:** Is iOS a mandatory production target (requiring immediate recreation of `Info.plist` and CocoaPods configuration), or is Android the primary development platform?

---

## 15. Recommended First Implementation Task

### Task Description: Baseline Compilation Fix & Safe Standalone YOLOv8n Initialization
This is the minimal, non-breaking first step to transition the repository from a non-building state to an executable on-device ML baseline.

### Exact Files to Inspect or Modify
1. **`frontend/gemini_live_app/lib/src/utilities/yolo_detector.dart`:**
   - **Change:** Add missing import at line 1:
     ```dart
     import 'package:flutter/foundation.dart';
     ```
   - **Rationale:** Resolves the 3 fatal compilation errors where `debugPrint` is undefined.
2. **`frontend/gemini_live_app/lib/main.dart`:**
   - **Change:** Wrap `dotenv.load(fileName: ".env")` in a `try/catch` block or check `File('.env').existsSync()`:
     ```dart
     try {
       await dotenv.load(fileName: ".env");
     } catch (e) {
       debugPrint('[Warning] .env file not found. Falling back to default environment.');
     }
     ```
   - **Rationale:** Prevents immediate unhandled runtime crash on app startup when `.env` is absent.
3. **`frontend/gemini_live_app/assets/models/yolov8n.tflite`:**
   - **Action:** Place a standard 640×640 Float32 `yolov8n.tflite` file into `assets/models/`.
   - **Rationale:** Resolves the asset bundle build failure in `pubspec.yaml`.

### Expected Behavior After Task Completion
- Running `flutter analyze` inside `frontend/gemini_live_app` will output **0 errors**.
- Running `flutter test` will successfully build the Flutter asset bundle and pass existing unit tests.
- The project will be ready to execute on-device inference on physical hardware.

### Concrete Acceptance Test
Run the following commands sequentially from `frontend/gemini_live_app`:
```bash
flutter analyze
flutter test
```
**Passing Condition:** Both commands exit with status code `0`.
