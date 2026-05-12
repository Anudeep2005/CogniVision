const requireRole = (role) => {
  return (req, res, next) => {
    if (!req.dbUser) {
      return res.status(500).json({ error: 'requireRole must be used after requireAuth' });
    }

    if (req.dbUser.role !== role) {
      return res.status(403).json({ error: `Forbidden: Requires ${role} role` });
    }

    next();
  };
};

module.exports = requireRole;
