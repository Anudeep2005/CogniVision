const User = require('../models/User');
const Location = require('../models/Location');
const Alert = require('../models/Alert');
const crypto = require('crypto');

exports.registerUser = async (req, res) => {
  const { firebaseUid, email, displayName, role } = req.body;
  
  try {
    let user = await User.findOne({ userId: firebaseUid });
    if (user) {
      return res.status(200).json(user);
    }

    user = new User({
      userId: firebaseUid,
      email: email,
      displayName: displayName,
      role: role
    });

    if (role === 'user') {
      user.pairCode = crypto.randomBytes(3).toString('hex').toUpperCase();
    }

    await user.save();
    res.status(201).json(user);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.pairUsers = async (req, res) => {
  const { userId, pairCode } = req.body;

  try {
    const guardian = await User.findOne({ userId: userId });
    const targetUser = await User.findOne({ pairCode: pairCode });

    if (!guardian || !targetUser) {
      return res.status(404).json({ error: 'User or Pair Code not found' });
    }

    if (guardian.role !== 'guardian') {
      return res.status(400).json({ error: 'Only guardians can pair with users' });
    }

    guardian.pairedWith = targetUser.userId;
    targetUser.pairedWith = guardian.userId;

    await guardian.save();
    await targetUser.save();

    res.status(200).json({ message: 'Paired successfully', pairedWith: targetUser.userId });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.saveLocation = async (req, res) => {
  const { userId, lat, lng } = req.body;
  try {
    const location = new Location({ userId, lat, lng });
    await location.save();
    res.status(201).json(location);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.triggerAlert = async (req, res) => {
  const { userId, type, message } = req.body;
  try {
    const alert = new Alert({ userId, type, message });
    await alert.save();
    res.status(201).json(alert);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
