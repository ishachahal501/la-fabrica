const crypto = require('crypto');
const Session = require('../models/Session');
const User = require('../models/User');

const protect = async (req, res, next) => {
    let token;
    if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
        try {
            token = req.headers.authorization.split(' ')[1];
            if (!token || token.trim().isEmpty) {
                return res.status(401).json({ message: 'Not authorized, no token' });
            }

            // Compute SHA-256 hash of incoming session token
            const tokenHash = crypto.createHash('sha256').update(token).digest('hex');

            // Find matching active session in MongoDB
            const session = await Session.findOne({ tokenHash });
            if (!session) {
                return res.status(401).json({ message: 'Not authorized, invalid or terminated session' });
            }

            // Verify session expiration
            if (session.expiresAt && session.expiresAt < new Date()) {
                await session.deleteOne();
                return res.status(401).json({ message: 'Not authorized, session expired' });
            }

            // Load authoritative user from MongoDB users collection
            const user = await User.findById(session.userId).select('-passwordHash -password');
            if (!user) {
                await session.deleteOne();
                return res.status(401).json({ message: 'Not authorized, user not found' });
            }

            // Update lastUsedAt timestamp asynchronously
            session.lastUsedAt = new Date();
            session.save().catch(() => {});

            req.user = user;
            req.session = session;
            return next();
        } catch (error) {
            console.error('Auth protect middleware error:', error);
            return res.status(401).json({ message: 'Not authorized, session token error' });
        }
    }

    if (!token) {
        return res.status(401).json({ message: 'Not authorized, no token' });
    }
};

const authorize = (...roles) => {
    return (req, res, next) => {
        if (!req.user || !roles.includes(req.user.role)) {
            return res.status(403).json({ message: `Role '${req.user?.role}' is not authorized to access this resource` });
        }
        next();
    };
};

module.exports = { protect, authorize };