const express = require('express');
const router = express.Router();
const User = require('../models/User');
const requireAuth = require('../middleware/requireAuth');

// POST /api/auth/register
router.post('/register', async (req, res) => {
  try {
    const { firebaseUid, role, displayName, email } = req.body;

    // Validate role
    if (role !== 'user' && role !== 'guardian') {
      return res.status(400).json({ error: 'Invalid role' });
    }

    const existingUser = await User.findOne({ firebaseUid });
    if (existingUser) {
      return res.status(409).json({ error: 'User already exists' });
    }

    const user = new User({
      firebaseUid,
      role,
      displayName,
      email
    });

    await user.save();
    res.status(201).json(user);
  } catch (error) {
    console.error('Registration Error:', error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

// GET /api/auth/me
router.get('/me', requireAuth, async (req, res) => {
  res.json(req.dbUser);
});

module.exports = router;
