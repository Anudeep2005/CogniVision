const mongoose = require('mongoose');

const alertSchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true,
    index: true,
  },
  type: {
    type: String,
    required: true,
    enum: ['SOS', 'ANOMALY'],
  },
  status: {
    type: String,
    required: true,
    enum: ['active', 'resolved'],
    default: 'active',
  },
}, { timestamps: true });

module.exports = mongoose.model('Alert', alertSchema);
