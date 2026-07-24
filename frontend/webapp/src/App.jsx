import React from "react";
import { BrowserRouter as Router, Routes, Route, Navigate } from "react-router-dom";
import Dashboard from "./pages/Dashboard";

export default function App() {
  return (
    <Router>
      <Routes>
        {/* Main tracking dashboard page */}
        <Route path="/" element={<Dashboard />} />
        
        {/* Future routes can be appended here */}
        
        {/* Redirection fallback for unmatched paths */}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Router>
  );
}
