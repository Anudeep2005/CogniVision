const User = require('../models/User');
const Location = require('../models/Location');
const Alert = require('../models/Alert');
const crypto = require('crypto');

// Generate a random pair code
const generatePairCode = () => {
  return crypto.randomBytes(4).toString('hex').toUpperCase();
};

const registerUser = async (req, res) => {
  try {
    const { userId, role } = req.body;
    
    let user = await User.findOne({ userId });
    if (user) {
      return res.status(400).json({ message: 'User already exists', user });
    }

    const pairCode = generatePairCode();
    user = new User({ userId, role, pairCode });
    await user.save();

    res.status(201).json({ message: 'User registered successfully', user });
  } catch (error) {
    res.status(500).json({ message: 'Server error', error: error.message });
  }
};

const pairUsers = async (req, res) => {
  try {
    const { userId, pairCode } = req.body;

    const user1 = await User.findOne({ userId }); // The one requesting the pair
    if (!user1) {
      return res.status(404).json({ message: 'Requesting user not found' });
    }

    const user2 = await User.findOne({ pairCode }); // The one being paired with
    if (!user2) {
      return res.status(404).json({ message: 'Invalid pair code' });
    }

    if (user1.userId === user2.userId) {
      return res.status(400).json({ message: 'Cannot pair with yourself' });
    }

    user1.pairedWith = user2.userId;
    user2.pairedWith = user1.userId;

    await user1.save();
    await user2.save();

    res.status(200).json({ message: 'Paired successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Server error', error: error.message });
  }
};

const saveLocation = async (req, res) => {
  try {
    const { userId, lat, lng, timestamp } = req.body;
    
    const location = new Location({ userId, lat, lng, timestamp });
    await location.save();

    res.status(201).json({ message: 'Location saved', location });
  } catch (error) {
    res.status(500).json({ message: 'Server error', error: error.message });
  }
};

const triggerAlert = async (req, res) => {
  try {
    const { userId, type } = req.body;
    
    const alert = new Alert({ userId, type, status: 'active' });
    await alert.save();

    // Note: Socket emission for real-time alert is handled separately, or we could emit it from here if we pass the io instance.

    res.status(201).json({ message: 'Alert triggered', alert });
  } catch (error) {
    res.status(500).json({ message: 'Server error', error: error.message });
  }
};

module.exports = {
  registerUser,
  pairUsers,
  saveLocation,
  triggerAlert
};
