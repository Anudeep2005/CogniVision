import React, { useState, useEffect } from "react";
import "../styles/App.css";

// SVG Icons
function CopyIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <polyline points="20 6 9 17 4 12"></polyline>
    </svg>
  );
}

function ClockIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <circle cx="12" cy="12" r="10"></circle>
      <polyline points="12 6 12 12 16 14"></polyline>
    </svg>
  );
}

export default function LocationCard({ lat, lng, connected, lastUpdated, onRecenter }) {
  const [copiedLat, setCopiedLat] = useState(false);
  const [copiedLng, setCopiedLng] = useState(false);
  const [localTime, setLocalTime] = useState("");
  const [elapsedText, setElapsedText] = useState("Never");

  // 1. Live Clock Timer
  useEffect(() => {
    const updateTime = () => {
      const now = new Date();
      setLocalTime(now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }));
    };
    
    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, []);

  // 2. Relative "Last Updated" Counter
  useEffect(() => {
    if (!lastUpdated) return;

    const calculateElapsed = () => {
      const diffSeconds = Math.floor((Date.now() - lastUpdated) / 1000);
      if (diffSeconds < 5) {
        setElapsedText("Just now");
      } else if (diffSeconds < 60) {
        setElapsedText(`${diffSeconds}s ago`);
      } else {
        const mins = Math.floor(diffSeconds / 60);
        const secs = diffSeconds % 60;
        setElapsedText(`${mins}m ${secs}s ago`);
      }
    };

    calculateElapsed();
    const interval = setInterval(calculateElapsed, 1000);
    return () => clearInterval(interval);
  }, [lastUpdated]);

  const handleCopy = (val, setCopiedFlag) => {
    navigator.clipboard.writeText(val.toString());
    setCopiedFlag(true);
    setTimeout(() => setCopiedFlag(false), 2000);
  };

  return (
    <div className="card-overlay glass-panel animate-fade-in">
      <div className="card-header">
        <div className="card-title-subtitle">
          <span className="card-category">Telemetry System</span>
          <h2 className="card-title">Live Tracking</h2>
        </div>
        <div className="live-clock-badge">
          <ClockIcon />
          <span>{localTime}</span>
        </div>
      </div>

      <div className="coordinate-group">
        <div className="coordinate-row">
          <div className="coord-label-val">
            <span className="coord-label">Latitude</span>
            <span className="coord-value">{lat.toFixed(6)}</span>
          </div>
          <button 
            className={`btn-copy ${copiedLat ? "copied" : ""}`} 
            onClick={() => handleCopy(lat, setCopiedLat)}
            title="Copy Latitude"
          >
            {copiedLat ? <CheckIcon /> : <CopyIcon />}
          </button>
        </div>

        <div className="coordinate-row">
          <div className="coord-label-val">
            <span className="coord-label">Longitude</span>
            <span className="coord-value">{lng.toFixed(6)}</span>
          </div>
          <button 
            className={`btn-copy ${copiedLng ? "copied" : ""}`} 
            onClick={() => handleCopy(lng, setCopiedLng)}
            title="Copy Longitude"
          >
            {copiedLng ? <CheckIcon /> : <CopyIcon />}
          </button>
        </div>
      </div>

      <div className="card-info-footer">
        <div className="info-item">
          <span>Signal Quality</span>
          <span className="info-item-value" style={{ color: connected ? "#2e7d32" : "#bba771" }}>
            {connected ? "Strong (Database Connected)" : "Weak (Reconnecting)"}
          </span>
        </div>
        <div className="info-item">
          <span>Last Update Stream</span>
          <span className="info-item-value">{elapsedText}</span>
        </div>
      </div>

      <button className="btn-primary-action" onClick={onRecenter}>
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polygon points="3 11 22 2 13 21 11 13 3 11"></polygon></svg>
        Recenter Map View
      </button>
    </div>
  );
}
