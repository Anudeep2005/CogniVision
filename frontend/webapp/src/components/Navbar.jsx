import React from "react";
import { SpaLeafIcon } from "./Loader";
import "../styles/App.css";

export default function Navbar({ connected }) {
  return (
    <nav className="navbar-overlay glass-panel">
      <div className="navbar-brand">
        <div className="navbar-logo-container">
          <SpaLeafIcon size={20} />
        </div>
        <h1 className="navbar-title">CogniVision Live GPS</h1>
      </div>
      
      <div className={`connection-badge ${connected ? "connected" : "disconnected"}`}>
        <span className={`status-pulse-dot ${connected ? "green" : "amber"}`}></span>
        {connected ? "Live Connected" : "Connecting..."}
      </div>
    </nav>
  );
}
