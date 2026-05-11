# 👁️ CogniVision: Comprehensive Project Architecture & Workflow

## 1. Executive Summary
**CogniVision** is a highly optimized, assistive technology mobile application built strictly for visually impaired individuals. The application serves as an "eyes-free," voice-controlled mobility companion. By leveraging a lightning-fast Voice Recognition engine, Text-to-Speech (TTS), and real-time GPS telemetry, it allows users to navigate the physical world safely and independently. The app prioritizes absolute simplicity: it boots directly into a full-screen tap-to-listen interface, stripping away complex menus and visual interactions.

---

## 2. Technology Stack

### Core Framework
* **Framework:** Flutter (Dart)
* **State Management:** Flutter Riverpod

### Geolocation & Routing
* **Maps:** `google_maps_flutter`, `flutter_polyline_points`
* **Geolocation:** `geolocator` (High-accuracy, background GPS tracking)
* **External APIs:** Google Maps Directions API (for calculating walking routes, step distances, and HTML turn-by-turn maneuvers).

### Accessibility & AI Voice Engine
* **Text-to-Speech:** `flutter_tts` (Handles all system feedback and navigation prompts)
* **Speech-to-Text:** `speech_to_text` (Configured for ultra-low latency dictation and partial result parsing)

### Networking & Telemetry
* **REST APIs:** `http`
* **Real-time Engine:** `socket_io_client` (WebSockets for emitting live SOS and location data)

---

## 3. End-to-End Workflow (How It Works)

### Phase 1: Instant Initialization
The application eliminates all visual menus. Upon launch:
1. It immediately requests highly accurate GPS and Microphone permissions.
2. It drops the user directly onto the `UserHomeScreen`.
3. The Voice Engine announces: *"Cognivision active. Tap anywhere on the screen to give a command."*

### Phase 2: The "Eyes-Free" Interface
The entire mobile screen is wrapped in a massive `GestureDetector`. This acts as a giant button, meaning the user does not need to search for specific UI elements to interact with the app.
* **Tap to Listen:** Tapping anywhere on the screen instantly activates the microphone.
* **Tap to Stop:** Tapping again instantly cuts the microphone and processes the captured speech, eliminating wait times.

### Phase 3: Voice Command Routing (`command_router.dart`)
Once the engine parses the user's speech, it routes the text to specific system functions:
* *"Navigate to Central Park"* -> Extracts the destination and triggers the Google Directions API.
* *"Help" / "Emergency"* -> Triggers an instant WebSocket SOS payload containing exact GPS coordinates.
* *"Start Navigation"* -> Commences the active turn-by-turn guidance.

### Phase 4: Turn-by-Turn Engine (`navigation_service.dart`)
This is the core functional loop of the application:
1. **Route Fetching:** The app calls the Google Directions API to fetch the route to the destination.
2. **Step Parsing:** The JSON response is decoded into an array of `NavigationStep` objects. Each step contains a starting coordinate, an ending coordinate, and a text instruction (e.g., "Turn left onto Elm St").
3. **Live Telemetry Loop:** As the user walks, a high-frequency geolocation stream tracks their physical coordinates.
4. **The Distance Threshold Trigger:** Using the Haversine formula, the app continuously calculates the exact physical distance between the user's current GPS location and the `endLocation` of their current maneuver.
5. **Automated Prompts:** When the distance to the next turn drops below **15 meters**, the app automatically triggers the TTS engine to read the instruction out loud, preparing the user for the turn before they reach the intersection.

---

## 4. Key Technical Optimizations

* **Ultra-Low Latency Voice Processing:** The `speech_to_text` engine is tuned for speed. By utilizing `ListenMode.deviceDefault` with `partialResults` enabled, the app captures audio accurately without prematurely timing out. The "Tap-to-Stop" override ensures users never have to wait for silence-detection timeouts.
* **Non-Blocking Architecture:** Running high-accuracy GPS tracking, WebSocket background streams, and voice processing simultaneously is computationally heavy. CogniVision uses Dart's asynchronous `Future` and `Stream` architecture alongside Riverpod state management to ensure the system never freezes.
* **Single-Purpose Efficiency:** By stripping out the multi-role (Guardian) system from the client app, the application binary is much smaller, cleaner, and strictly optimized for the specific needs of the visually impaired end-user.
