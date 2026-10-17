const crypto = require('crypto');
const Session = require('../models/Session');
const User = require('../models/User');

const protect = async (req, res, next) => {
    const authorization = req.headers.authorization || '';
    const [scheme, token] = authorization.trim().split(/\s+/);

    if (scheme?.toLowerCase() !== 'bearer' || !token) {
        return res.status(401).json({
            message: 'Authentication required'
        });
    }

    try {
        // Compute SHA-256 hash of incoming session token
        const tokenHash = crypto.createHash('sha256').update(token.trim()).digest('hex');

        // Find matching active session in MongoDB
        const session = await Session.findOne({ tokenHash });
        if (!session) {
            return res.status(401).json({ message: 'Not authorized, invalid or terminated session' });
        }

        // Verify session expiration
        if (!session.expiresAt || session.expiresAt <= new Date()) {
            await session.deleteOne().catch(() => {});
            return res.status(401).json({
                message: 'Session expired'
            });
        }

        // Load authoritative user from MongoDB users collection (never return passwordHash)
        const user = await User.findById(session.userId).select('-passwordHash -password');
        if (!user) {
            await session.deleteOne().catch(() => {});
            return res.status(401).json({ message: 'Not authorized, user not found' });
        }

        // Throttled lastUsedAt update (only update once every 5 minutes to reduce unnecessary DB writes)
        const now = Date.now();
        if (!session.lastUsedAt || (now - new Date(session.lastUsedAt).getTime()) > 5 * 60 * 1000) {
            session.lastUsedAt = new Date(now);
            session.save().catch(() => {});
        }

        req.user = user;
        req.session = session;
        return next();
    } catch (error) {
        console.error('Auth protect middleware error:', error.message || error);
        const isDbError = error.name?.includes('Mongo') || 
                          error.name === 'MongooseError' ||
                          error.name === 'MongoServerSelectionError' ||
                          error.name === 'MongoNetworkError' ||
                          error.name === 'MongoTimeoutError';
        if (isDbError) {
            return res.status(503).json({ message: 'Database service temporarily unavailable' });
        }
        return res.status(500).json({ message: 'Internal server error during authentication' });
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