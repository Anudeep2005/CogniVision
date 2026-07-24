import React, { useState } from "react";
import useLiveLocation from "../hooks/useLiveLocation";
import Navbar from "../components/Navbar";
import LocationCard from "../components/LocationCard";
import MapView from "../components/MapView";
import Loader from "../components/Loader";
import "../styles/App.css";

// SVG Icon for warning/error
function ErrorIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <circle cx="12" cy="12" r="10"></circle>
      <line x1="12" y1="8" x2="12" y2="12"></line>
      <line x1="12" y1="16" x2="12.01" y2="16"></line>
    </svg>
  );
}

export default function Dashboard() {
  const { location, loading, error, connected, lastUpdated } = useLiveLocation();
  const [recenterTrigger, setRecenterTrigger] = useState(0);

  // Recenter trigger handler
  const handleRecenter = () => {
    setRecenterTrigger((prev) => prev + 1);
  };

  // 1. Loading Screen
  if (loading) {
    return <Loader message="Connecting to CogniVision..." />;
  }

  // 2. Error Screen
  if (error) {
    return (
      <div className="loader-wrapper luxury-bg-container">
        {/* Decorative background blobs */}
        <div className="luxury-blob luxury-blob-1"></div>
        <div className="luxury-blob luxury-blob-2"></div>

        <div className="error-card glass-panel animate-fade-in">
          <div className="error-icon-box">
            <ErrorIcon />
          </div>
          <h2 className="error-title">Database Error</h2>
          <p className="error-message">
            {error} <br />
            Please check your network connection and ensure your Firebase Realtime Database path 
            <code> Tracking/CurrentUser</code> contains valid coordinates.
          </p>
          <button className="btn-retry" onClick={() => window.location.reload()}>
            Retry Connection
          </button>
        </div>
      </div>
    );
  }

  // 3. Render Dashboard View
  const lat = location?.lat ?? 17.432141;
  const lng = location?.lng ?? 78.341221;

  return (
    <div className="dashboard-container">
      {/* Interactive Map (acts as full viewport background) */}
      <MapView 
        location={location} 
        recenterTrigger={recenterTrigger} 
      />

      {/* Floating Overlay Header/Navbar */}
      <Navbar connected={connected} />

      {/* Floating Location Card Overlay */}
      <LocationCard
        lat={lat}
        lng={lng}
        connected={connected}
        lastUpdated={lastUpdated}
        onRecenter={handleRecenter}
      />
    </div>
  );
}
