# CogniVision IoT Firmware

This directory contains the firmware for the ESP32-based GPS tracking system used in the CogniVision project.

## Components
- **ESP32**: Main microcontroller.
- **NEO-6M GPS**: GPS module for location tracking.

## Libraries Required (Arduino IDE)
- `TinyGPS++`
- `WiFi`
- `HTTPClient`

## Setup
1. Open `location.ino` in Arduino IDE.
2. Update the `ssid` and `password` with your WiFi credentials.
3. (Optional) Update the `firebaseURL` if you are using your own Firebase Realtime Database.
4. Upload to your ESP32.

## How it works
The firmware captures GPS coordinates and sends them to the Firebase Realtime Database every 2 seconds. The Flutter application then listens to this database to provide live tracking for guardians.
