CogniVision - AI-Powered Visual Assistant for Visually Impaired Users
Overview

This project implements a real-time AI-powered visual assistant designed to aid visually impaired users in understanding and navigating their surroundings.

The application captures live video and audio input from the device, streams it to a multimodal AI model via Vertex AI, and returns low-latency audio responses that describe the environment and provide actionable guidance.

The current implementation focuses on a live AI assistant capable of real-time perception and response.

Key Features
Real-time multimodal interaction using video and audio input
Low-latency streaming responses (sub-second performance)
Context-aware scene understanding
Audio-based guidance for navigation and obstacle awareness
Continuous bidirectional communication with the AI model
System Architecture

The system is designed around a streaming pipeline that enables continuous interaction between the user and the AI model.

Data Flow

Camera and microphone input are captured on the device and streamed to the backend:

Camera (Video Frames) + Microphone (Audio Stream)
                ↓
      Real-time Streaming (Flutter App)
                ↓
         Vertex AI Platform
                ↓
   Gemini Live Multimodal Model
                ↓
     Streaming Audio Response
                ↓
           Audio Playback
Technology Stack
Frontend
Flutter (Dart)
Riverpod (state management)
Backend / AI
Firebase AI integration
Vertex AI (Google Cloud)
Model
gemini-live-2.5-flash-native-audio
Media Handling
Camera plugin (video frames)
Audio streaming (input/output)
SoLoud (low-latency audio playback)
Why Vertex AI

This project relies on real-time multimodal streaming capabilities provided by Vertex AI.

Standard request-response APIs are insufficient for this use case due to:

High latency
Lack of bidirectional streaming
No support for continuous audio interaction

Vertex AI enables:

Live sessions with the model
Simultaneous audio and video input
Streaming audio output
Sub-second response times
Model Selection

The system uses:

gemini-live-2.5-flash-native-audio

This model was chosen because:

It supports real-time streaming interaction
It provides native audio output (no additional TTS required)
It is optimized for low latency (Flash variant)
It can process multimodal input (audio + visual) simultaneously
Current Functionality

The current version implements:

Live AI assistant for environmental awareness
Scene description based on camera input
Audio-based responses for user guidance
Continuous interaction using a live session
Project Structure (Relevant Components)
lib/
 ├── video_input.dart        # Camera capture and frame streaming
 ├── audio_input.dart        # Microphone streaming
 ├── audio_output.dart       # Real-time audio playback
 ├── providers.dart          # State management (Riverpod)
 ├── main live controller    # Session orchestration and AI interaction
Setup Instructions
Prerequisites
Flutter SDK
Firebase project configured
Vertex AI access enabled
Android/iOS device with camera and microphone
Steps
Clone the repository

Install dependencies:

flutter pub get
Configure Firebase for your project
Enable Vertex AI and Gemini APIs

Run the application:

flutter run
Security Considerations
API keys are not stored in the client application
Access to Vertex AI is handled through secure Firebase integration
No sensitive user data is stored persistently
Usage is restricted to assistive functionality
Limitations
Requires active internet connection
Depends on Vertex AI access for real-time functionality
Performance may vary based on network conditions
Future Work
GPS-based navigation with route guidance
Voice-controlled in-app navigation
Face recognition for known individuals
IoT integration (external sensors for proximity detection)
Context memory for improved guidance continuity
Use Case

This system is designed to improve independence and situational awareness for visually impaired individuals by providing real-time, AI-driven environmental understanding.
