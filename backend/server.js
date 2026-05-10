require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// Models
const UserSchema = new mongoose.Schema({
  firebaseUid: { type: String, required: true, unique: true },
  email: { type: String, required: true },
  displayName: { type: String },
  role: { type: String, enum: ['user', 'guardian'], default: 'user' },
  guardianCode: { type: String, unique: true, sparse: true },
  pairedGuardianId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  lastLocation: {
    lat: Number,
    lng: Number,
    timestamp: Date
  }
});

const User = mongoose.model('User', UserSchema);

const SosAlertSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  location: { lat: Number, lng: Number },
  status: { type: String, enum: ['active', 'resolved'], default: 'active' },
  timestamp: { type: Date, default: Date.now }
});

const SosAlert = mongoose.model('SosAlert', SosAlertSchema);

// Connect to MongoDB
mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/cognivision', {
  useNewUrlParser: true,
  useUnifiedTopology: true,
}).then(() => console.log('Connected to MongoDB'))
  .catch(err => console.error('MongoDB connection error:', err));

// Routes
app.post('/api/auth/register', async (req, res) => {
  try {
    const { firebaseUid, email, displayName, role } = req.body;
    
    let user = await User.findOne({ firebaseUid });
    if (!user) {
      user = new User({ firebaseUid, email, displayName, role });
      
      // Generate a guardian code for visually impaired users
      if (role === 'user') {
        user.guardianCode = Math.random().toString(36).substring(2, 8).toUpperCase();
      }
      
      await user.save();
    }
    
    res.status(201).json(user);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/sos/trigger', async (req, res) => {
  try {
    const { firebaseUid, location } = req.body;
    const user = await User.findOne({ firebaseUid });
    
    if (!user) return res.status(404).json({ error: 'User not found' });
    
    const alert = new SosAlert({
      userId: user._id,
      location: location,
    });
    
    await alert.save();
    
    // In a real app, trigger push notification to pairedGuardianId here
    
    res.status(200).json({ success: true, alertId: alert._id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/location/update', async (req, res) => {
  try {
    const { firebaseUid, lat, lng } = req.body;
    const user = await User.findOneAndUpdate(
      { firebaseUid },
      { 
        lastLocation: { lat, lng, timestamp: new Date() }
      },
      { new: true }
    );
    
    res.status(200).json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Pairing route
app.post('/api/guardian/pair', async (req, res) => {
  try {
    const { guardianFirebaseUid, userGuardianCode } = req.body;
    
    const guardian = await User.findOne({ firebaseUid: guardianFirebaseUid, role: 'guardian' });
    if (!guardian) return res.status(404).json({ error: 'Guardian not found' });
    
    const user = await User.findOne({ guardianCode: userGuardianCode, role: 'user' });
    if (!user) return res.status(404).json({ error: 'Invalid pairing code' });
    
    user.pairedGuardianId = guardian._id;
    await user.save();
    
    res.status(200).json({ success: true, message: 'Successfully paired' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
