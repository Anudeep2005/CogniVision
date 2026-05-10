const express = require('express');
const router = express.Router();
const User = require('../models/User');
const requireAuth = require('../middleware/requireAuth');

// POST /api/auth/register
router.post('/register', async (req, res) => {
  const { firebaseUid, role, displayName, email } = req.body;

  const existingUser = await User.findOne({ userId: firebaseUid });
  if (existingUser) {
    return res.status(409).json({ error: 'User already exists' });
  }

  const user = new User({
    userId: firebaseUid,
    role,
    displayName,
    email
  });

  if (role === 'user') {
    const crypto = require('crypto');
    user.pairCode = crypto.randomBytes(3).toString('hex').toUpperCase();
  }

  await user.save();
  res.status(201).json(user);
});

// GET /api/auth/me
router.get('/me', requireAuth, async (req, res) => {
  res.json(req.dbUser);
});

module.exports = router;
