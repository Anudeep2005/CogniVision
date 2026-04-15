# CogniVision

> An AI-powered visual assistant for real-time environmental awareness, built for visually impaired users.

---

## Overview

CogniVision captures live video and audio input, streams it to a multimodal AI model via Vertex AI, and returns low-latency audio responses that provide environmental awareness and actionable guidance.

The system is designed around continuous, bidirectional interaction — not one-shot queries — enabling a persistent, real-time assistant experience.

---

## Key Features

- Real-time multimodal interaction using simultaneous video and audio input
- Sub-second latency with streaming responses
- Context-aware scene understanding
- Audio-based guidance for navigation and obstacle awareness
- Continuous bidirectional communication with the AI model

---

## System Architecture

### Data Flow

```
Camera (Video Frames) + Microphone (Audio Stream)
                │
                ▼
      Real-time Streaming (Flutter App)
                │
                ▼
         Vertex AI Platform
                │
                ▼
   Gemini Live Multimodal Model
                │
                ▼
     Streaming Audio Response
                │
                ▼
           Audio Playback
```

### Technology Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart), Riverpod |
| AI Backend | Firebase AI integration, Vertex AI |
| Model | `gemini-live-2.5-flash-native-audio` |
| Media | Camera plugin, Audio streaming, SoLoud |

---

## Why Vertex AI

This project depends on real-time multimodal streaming, which is only available through Vertex AI. Traditional request-response APIs are insufficient due to high latency, lack of bidirectional streaming, and no support for continuous audio interaction.

Vertex AI enables:

- Live sessions with persistent model state
- Simultaneous audio and video input
- Streaming audio output
- Sub-second response times

---

## Model Selection

**`gemini-live-2.5-flash-native-audio`**

| Requirement | How it is met |
|---|---|
| Real-time interaction | Native streaming session support |
| Audio output | Native audio generation (no TTS pipeline needed) |
| Low latency | Flash variant, optimized for speed |
| Multimodal input | Handles audio and visual simultaneously |

---

## Current Functionality

- Live AI assistant for environmental awareness
- Scene understanding from camera input
- Audio-based guidance for navigation
- Continuous interaction via a persistent live session

---

## Project Structure

```
lib/
 ├── video_input.dart        # Camera capture and frame streaming
 ├── audio_input.dart        # Microphone streaming
 ├── audio_output.dart       # Real-time audio playback
 ├── providers.dart          # State management (Riverpod)
 └── main_controller.dart    # Session orchestration and AI interaction
```

---

## Setup Instructions

### Prerequisites

- Flutter SDK
- Firebase project configured with Vertex AI enabled
- Physical device with camera and microphone access

### Installation

```bash
git clone <your-repo-url>
cd <repo-name>
flutter pub get
```

### Run

```bash
flutter run
```

---

## Security Considerations

- API keys are not exposed in the client
- All requests are routed through secure Firebase integration
- No sensitive user data is stored or logged
- Usage is scoped to assistive functionality only

---

## Limitations

- Requires an active internet connection
- Core functionality depends on Vertex AI availability
- Response quality and latency vary with network conditions

---

## Future Work

- GPS-based navigation assistance
- Voice-controlled in-app navigation
- Face recognition for known individuals
- IoT integration with external sensors
- Context memory for improved session continuity

---

## Use Case

CogniVision is designed to improve independence and situational awareness for visually impaired individuals through real-time AI-driven perception and audio guidance.
