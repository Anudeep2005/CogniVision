#include <WiFi.h>
#include <HTTPClient.h>
#include <TinyGPS++.h>
#include <HardwareSerial.h>

// WiFi
const char* ssid = "real";
const char* password = "anudeep1";

// Node.js Backend URL (Replace with your server's IP)
const char* backendURL = "http://YOUR_SERVER_IP:3000/api/location/update";

// GPS
TinyGPSPlus gps;
HardwareSerial gpsSerial(2);

unsigned long lastSend = 0;

void setup() {
  Serial.begin(115200);
  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);

  // Connect WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(500);
  }

  Serial.println("\nWiFi Connected");
}

void loop() {
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }

  // Send every 2 seconds
  if (millis() - lastSend > 2000) {
    lastSend = millis();

    if (gps.location.isValid()) {
      float lat = gps.location.lat();
      float lng = gps.location.lng();

      Serial.println("Sending to Firebase...");
      Serial.println(lat);
      Serial.println(lng);

      if (WiFi.status() == WL_CONNECTED) {
        HTTPClient http;

        http.begin(backendURL);
        http.addHeader("Content-Type", "application/json");

        // JSON payload matching Node.js schema
        String json = "{";
        json += "\"firebaseUid\":\"user_123_firebase\",";
        json += "\"lat\":" + String(lat, 6) + ",";
        json += "\"lng\":" + String(lng, 6);
        json += "}";

        int httpResponseCode = http.POST(json);

        Serial.print("HTTP Response: ");
        Serial.println(httpResponseCode);

        http.end();
      }
    } 
    else {
      Serial.println("Waiting for GPS fix...");
    }
  }
}