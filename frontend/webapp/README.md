# CogniVision Live GPS Telemetry Dashboard

A modern, high-fidelity React companion web dashboard to the CogniVision Flutter mobile application. This dashboard connects directly to Firebase Realtime Database to display the live GPS coordinates of the target user on a premium, glassmorphic interactive map in real-time.

---

## 🎨 Design Language & Visual System

This web companion matches the exact aesthetic design system extracted from the main CogniVision Flutter application (`frontend/gemini_live_app`):

- **Luxury Palette:** Primary deep emerald green (`#20563F`), secondary gold (`#C8A96B`), and a soft ivory green background (`#F5F7F2`).
- **Luxury Background:** Animated floating glass blobs (mint green & translucent gold) layered over a faint stardust grain pattern.
- **Glassmorphism Overlay:** Semi-transparent white card panels (`rgba(255,255,255,0.85)`) with backdrop filtering, rounded corners (`20px`), and fine borders (`rgba(32, 86, 63, 0.12)`).
- **Branding:** Replicates the uppercase letter-spaced headings (`letter-spacing: 2px`) and the circular leaf spa logo (`Icons.spa_rounded` styling).
- **Responsive Overlays:** Displays full-viewport mapping with overlapping modular control panels (floating side-by-side on desktop, sliding bottom-sheet on mobile).

---

## 🚀 Core Features

- **Continuous Live Synchronization:** Seamless listening for coordinates at `Tracking/CurrentUser` using Firebase SDK v11's modular `onValue()` listeners without full-page refreshes.
- **Visual Connection Indicator:** Monitors the database connection status (`.info/connected`) in real-time, flashing orange during reconnect attempts and solid green when active.
- **Pulsing GPS Marker:** Implements a custom SVG radar marker (emerald core, gold/mint pulsing rings) styled via Leaflet `divIcon` to bypass default Leaflet image asset bundler path resolution bugs.
- **Smart Map Control:** Automatically pans map position when the user moves short distances (continuous glide) and flies with arc zooms for larger telemetry changes.
- **Local Telemetry & Utilities:**
  - **Live Digital Clock:** Local system time updated every second.
  - **Elapsed Stream Counter:** Dynamic relative counter showing time since last database update (e.g. "Just now", "8s ago").
  - **Quick Copy Coordinates:** Quick button copies latitude/longitude directly to clipboard.
  - **Recenter View Button:** Instantly centers the viewport on the active marker.

---

## 🛠️ Project Setup

### 1. Prerequisites
Ensure you have [Node.js](https://nodejs.org/) installed (v18+ recommended).

### 2. Configure Environment Variables
Create a `.env` file in the root of the React app (`frontend/webapp/.env`) and add your Firebase credentials:
```env
VITE_FIREBASE_API_KEY=your_firebase_api_key_here
VITE_FIREBASE_AUTH_DOMAIN=your_project_id.firebaseapp.com
VITE_FIREBASE_DATABASE_URL=https://your_project_id-default-rtdb.firebaseio.com
VITE_FIREBASE_PROJECT_ID=your_project_id
VITE_FIREBASE_STORAGE_BUCKET=your_project_id.firebasestorage.app
VITE_FIREBASE_MESSAGING_SENDER_ID=your_messaging_sender_id
VITE_FIREBASE_APP_ID=your_firebase_app_id
```
*(A pre-populated configuration based on the Flutter project's configurations has already been initialized in `.env`)*

### 3. Installation
Install project dependencies:
```bash
npm install
```
*(In React 19 environments, packages are installed with `--legacy-peer-deps` to ignore peer-dependency version mismatches for older leaf libraries)*

### 4. Running Locally
Run the Vite development server:
```bash
npm run dev
```
Open [http://localhost:5173](http://localhost:5173) in your browser.

### 5. Production Compilation
Compile the application for production:
```bash
npm run build
```
This outputs minified static assets to the `dist/` directory ready for static hosting.
