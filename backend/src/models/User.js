const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true,
    unique: true,
  },
  role: {
    type: String,
    required: true,
    enum: ['user', 'guardian'],
  },
  email: {
    type: String,
    required: true,
  },
  displayName: {
    type: String,
  },
  pairCode: {
    type: String,
    unique: true,
    sparse: true,
  },
  pairedWith: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    default: null,
  },
  lastLocation: {
    lat: Number,
    lng: Number,
    timestamp: Date
  }
}, { timestamps: true });

module.exports = mongoose.model('User', userSchema);
