import React, { useEffect, useRef } from "react";
import { MapContainer, TileLayer, Marker, Popup, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import "../styles/App.css";

// Create custom pulsing GPS marker using Leaflet divIcon
const pulseIcon = L.divIcon({
  className: "custom-gps-marker",
  html: `<div class="gps-pulse-ring"></div><div class="gps-marker-dot"></div>`,
  iconSize: [32, 32],
  iconAnchor: [16, 16],
  popupAnchor: [0, -16]
});

// Map controller to handle smooth auto-recentering
function MapController({ center, triggerRecenter }) {
  const map = useMap();
  const lastCenterRef = useRef(center);

  useEffect(() => {
    if (!center) return;

    const latLng = L.latLng(center[0], center[1]);
    const currentCenter = map.getCenter();
    
    // Calculate distance in meters between current view center and new coordinate
    const distance = currentCenter.distanceTo(latLng);

    // If coordinates changed or manual recenter is triggered
    if (distance > 2) {
      // If the jump is larger than 1.5km, fly smoothly. Otherwise, pan/glide.
      if (distance > 1500) {
        map.flyTo(latLng, 16, {
          animate: true,
          duration: 1.8
        });
      } else {
        map.panTo(latLng, {
          animate: true,
          duration: 1.2
        });
      }
    }
    lastCenterRef.current = center;
  }, [center, map, triggerRecenter]);

  return null;
}

export default function MapView({ location, recenterTrigger }) {
  // Coordinates fallback if not loaded
  const position = location ? [location.lat, location.lng] : [17.432141, 78.341221];

  return (
    <div className="map-viewport">
      <MapContainer
        center={position}
        zoom={16}
        zoomControl={false} // Disable default top-left control to place it custom
        className="map-element"
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        {location && (
          <Marker position={position} icon={pulseIcon}>
            <Popup className="custom-popup">
              <div style={{ textAlign: "center", fontWeight: "bold", color: "#20563F" }}>
                Current User
              </div>
              <div style={{ fontSize: "11px", color: "#355847", marginTop: "4px" }}>
                Active GPS Node
              </div>
            </Popup>
          </Marker>
        )}

        <MapController center={position} triggerRecenter={recenterTrigger} />
      </MapContainer>
    </div>
  );
}
