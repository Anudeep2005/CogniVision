const User = require('../models/User');

const setupSockets = (io) => {
  io.on('connection', (socket) => {
    console.log(`New client connected: ${socket.id}`);

    // User joins their own room to receive personal events (like pairing confirmation, alerts from their pair)
    socket.on('join', (userId) => {
      socket.join(userId);
      console.log(`User ${userId} joined their room`);
    });

    socket.on('LOCATION_UPDATE', async (data) => {
      // data: { userId, lat, lng, timestamp }
      try {
        const user = await User.findOne({ userId: data.userId });
        if (user && user.pairedWith) {
          // Send location update to the paired guardian
          io.to(user.pairedWith).emit('LOCATION_UPDATE', data);
        }
      } catch (error) {
        console.error('Error handling LOCATION_UPDATE:', error);
      }
    });

    socket.on('SOS_ALERT', async (data) => {
      // data: { userId, type, status }
      try {
        console.log(`SOS_ALERT from ${data.userId}`);
        const user = await User.findOne({ userId: data.userId });
        if (user && user.pairedWith) {
          // Send alert to the paired guardian
          io.to(user.pairedWith).emit('SOS_ALERT', data);
        }
      } catch (error) {
        console.error('Error handling SOS_ALERT:', error);
      }
    });

    socket.on('disconnect', () => {
      console.log(`Client disconnected: ${socket.id}`);
    });
  });
};

module.exports = setupSockets;
