const mongoose = require('mongoose');

const locationSchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true,
    index: true,
  },
  lat: {
    type: Number,
    required: true,
  },
  lng: {
    type: Number,
    required: true,
  },
  timestamp: {
    type: Number,
    required: true,
  },
}, { timestamps: true });

module.exports = mongoose.model('Location', locationSchema);
