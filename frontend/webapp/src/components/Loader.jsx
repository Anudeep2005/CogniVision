import React from "react";
import "../styles/App.css";

// SVG representing the spa-leaf icon matching Icons.spa_rounded from the Flutter application
export function SpaLeafIcon({ size = 24, ...props }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      {...props}
    >
      <path d="M12 22C12 22 20 18 20 12C20 9.8 19.2 8.2 18 7C16.8 5.8 15.2 5 13 5C10.8 5 9.2 5.8 8 7C6.8 8.2 6 9.8 6 12C6 18 12 22 12 22Z" />
      <path d="M12 5V22" />
      <path d="M12 12C12 12 15 10 17 11" />
      <path d="M12 15C12 15 9 13 7 14" />
    </svg>
  );
}

export default function Loader({ message = "Connecting to CogniVision..." }) {
  return (
    <div className="loader-wrapper luxury-bg-container">
      {/* Luxury Background elements */}
      <div className="luxury-blob luxury-blob-1"></div>
      <div className="luxury-blob luxury-blob-2"></div>

      <div className="loader-logo-ring">
        <SpaLeafIcon />
      </div>
      <div className="loader-text">{message}</div>
      <div className="loader-subtext">Initializing Realtime GPS connection...</div>
    </div>
  );
}
