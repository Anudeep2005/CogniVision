require('dotenv').config();
require('express-async-errors');
const express = require('express');
const http = require('http');
const cors = require('cors');
const { Server } = require('socket.io');
const connectDB = require('./config/db');
const { initFirebase } = require('./config/firebase');
const authRoutes = require('./routes/auth');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] }
});

const PORT = process.env.PORT || 3000;

// Connect to Database and Firebase
connectDB();
initFirebase();

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.use('/api/auth', authRoutes);

// 404 Handler
app.use((req, res, next) => {
  res.status(404).json({ error: 'Not Found' });
});

// Global Error Handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  const status = err.status || 500;
  res.status(status).json({
    error: err.message || 'Internal Server Error',
  });
});

// Socket.IO — real-time location and SOS relay
io.on('connection', (socket) => {
  console.log(`[Socket.IO] Client connected: ${socket.id}`);

  // User joins their personal room so guardian can target them
  socket.on('join', (userId) => {
    socket.join(userId);
    console.log(`[Socket.IO] User ${userId} joined room`);
  });

  // Relay live location to all listeners in the user's room
  socket.on('LOCATION_UPDATE', (data) => {
    const { userId } = data;
    if (!userId) return;
    socket.to(userId).emit('LOCATION_UPDATE', data);
  });

  // Relay SOS alert to all listeners in the user's room
  socket.on('SOS_ALERT', (data) => {
    const { userId } = data;
    if (!userId) return;
    console.warn(`[Socket.IO] SOS received from user ${userId}`);
    socket.to(userId).emit('SOS_ALERT', data);
  });

  socket.on('disconnect', () => {
    console.log(`[Socket.IO] Client disconnected: ${socket.id}`);
  });
});

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

module.exports = { app, server, io };
