module.exports = (io) => {
  io.on('connection', (socket) => {
    console.log('A user connected:', socket.id);

    socket.on('join', (userId) => {
      socket.join(userId);
      console.log(`User ${userId} joined their room`);
    });

    socket.on('LOCATION_UPDATE', (data) => {
      // data: { userId, lat, lng, timestamp }
      console.log('Location Update:', data);
      // Broadcast to the user's room (so the guardian can see it)
      // In a real app, you'd find the guardian's userId and emit to them
      // For simplicity, we emit to the same room or a paired room
      socket.broadcast.emit('LOCATION_UPDATE', data);
    });

    socket.on('SOS_ALERT', (data) => {
      // data: { userId, type, status }
      console.log('SOS ALERT:', data);
      // Broadcast SOS to everyone or specifically to paired guardian
      socket.broadcast.emit('SOS_ALERT', data);
    });

    socket.on('disconnect', () => {
      console.log('User disconnected');
    });
  });
};
