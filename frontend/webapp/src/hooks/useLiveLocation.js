import { useState, useEffect } from "react";
import { ref, onValue } from "firebase/database";
import { db } from "../services/firebase";

/**
 * Custom hook to listen to the live GPS location of CurrentUser inside Firebase Realtime Database.
 * Also monitors the real-time Firebase connection status.
 *
 * @returns {object} { location: { lat, lng }, loading, error, connected, lastUpdated }
 */
export default function useLiveLocation() {
  const [location, setLocation] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [connected, setConnected] = useState(false);
  const [lastUpdated, setLastUpdated] = useState(null);

  useEffect(() => {
    // 1. Monitor Firebase connection status
    const connectedRef = ref(db, ".info/connected");
    const unsubscribeConnected = onValue(
      connectedRef,
      (snap) => {
        setConnected(snap.val() === true);
      },
      (err) => {
        console.error("Firebase connection status error: ", err);
      }
    );

    // 2. Monitor GPS location coordinates (tracking/currentUser)
    const locationRef = ref(db, "tracking/currentUser");
    const unsubscribeLocation = onValue(
      locationRef,
      (snapshot) => {
        const data = snapshot.val();
        if (data && typeof data.lat === "number" && typeof data.lng === "number") {
          setLocation({ lat: data.lat, lng: data.lng });
          setLastUpdated(Date.now());
          setError(null);
        } else if (!data) {
          setError("No tracking data available for currentUser in Firebase.");
        } else {
          setError("Invalid tracking data format (expected lat and lng numbers).");
        }
        setLoading(false);
      },
      (err) => {
        console.error("Firebase location subscription error: ", err);
        setError("Failed to stream GPS location from Firebase database.");
        setLoading(false);
      }
    );

    // Clean up subscriptions on unmount
    return () => {
      unsubscribeConnected();
      unsubscribeLocation();
    };
  }, []);

  return { location, loading, error, connected, lastUpdated };
}
