const admin = require('../config/firebase');
const User = require('../models/User');

const requireAuth = async (req, res, next) => {
  if (admin.apps.length === 0) {
    return res.status(503).json({ error: 'Auth Service Unavailable: Firebase not configured' });
  }

  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized: No token provided' });
  }

  const idToken = authHeader.split('Bearer ')[1];

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const firebaseUid = decodedToken.uid;

    const user = await User.findOne({ userId: firebaseUid });

    if (!user) {
      return res.status(404).json({ error: 'User not found in database' });
    }

    req.dbUser = user;
    next();
  } catch (error) {
    console.error('Error verifying token:', error);
    res.status(401).json({ error: 'Unauthorized: Invalid token' });
  }
};

module.exports = requireAuth;
