const express = require('express');
const crypto = require('crypto');
const User = require('../models/User');
const Session = require('../models/Session');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

// Helper to generate random raw session token and SHA-256 hash
function generateSessionToken() {
    const rawToken = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
    return { rawToken, tokenHash };
}

// GET /api/auth/designers - List available designer accounts (useful for inventory assignedDesignerId)
router.get('/designers', async (req, res) => {
    try {
        const designers = await User.find({ role: 'designer' }).select('name email _id');
        res.json(designers);
    } catch (error) {
        res.status(500).json({ message: 'Server error fetching designers' });
    }
});

// POST /api/auth/register
router.post('/register', async (req, res) => {
    const { name, email, password, role = 'designer', assignedDesignerId } = req.body;
    try {
        if (!name || !email || !password) {
            return res.status(400).json({ message: 'Please fill in all required fields' });
        }

        const normalizedEmail = email.toLowerCase().trim();
        const validRoles = ['designer', 'inventory'];
        if (!validRoles.includes(role)) {
            return res.status(400).json({ message: 'Invalid user role' });
        }

        const userExists = await User.findOne({ email: normalizedEmail });
        if (userExists) {
            return res.status(400).json({ message: 'User with this email already exists' });
        }

        let assignedDesigner = assignedDesignerId;
        if (role === 'inventory') {
            if (assignedDesigner) {
                const designerUser = await User.findOne({ _id: assignedDesigner, role: 'designer' });
                if (!designerUser) {
                    return res.status(400).json({ message: 'Assigned designer does not exist or is not a designer' });
                }
            } else {
                const firstDesigner = await User.findOne({ role: 'designer' });
                if (firstDesigner) {
                    assignedDesigner = firstDesigner._id;
                }
            }
        }

        // Create User document with passwordHash
        const user = await User.create({
            name: name.trim(),
            email: normalizedEmail,
            passwordHash: password,
            role,
            assignedDesignerId: role === 'inventory' ? assignedDesigner : null
        });

        // Generate session token and store tokenHash in sessions collection
        const { rawToken, tokenHash } = generateSessionToken();
        const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days TTL

        await Session.create({
            userId: user._id,
            tokenHash,
            expiresAt,
            userAgent: req.headers['user-agent'] || '',
            ipAddress: req.ip || ''
        });

        res.status(201).json({
            token: rawToken,
            user: {
                id: user._id,
                name: user.name,
                email: user.email,
                role: user.role,
                assignedDesignerId: user.assignedDesignerId
            }
        });
    } catch (error) {
        console.error("REGISTER ERROR:", error);
        res.status(500).json({ message: 'Server error', details: error.message });
    }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
    const { email, password, expectedRole } = req.body;
    try {
        if (!email || !password) {
            return res.status(400).json({ message: 'Please provide email and password' });
        }

        const normalizedEmail = email.toLowerCase().trim();
        const user = await User.findOne({ email: normalizedEmail });
        if (!user) return res.status(400).json({ message: 'Invalid credentials' });

        const isMatch = await user.matchPassword(password);
        if (!isMatch) return res.status(400).json({ message: 'Invalid credentials' });

        if (expectedRole && user.role !== expectedRole) {
            return res.status(403).json({
                message: `Access denied. Account role is '${user.role}', not '${expectedRole}'.`
            });
        }

        // Generate new session token & tokenHash in MongoDB
        const { rawToken, tokenHash } = generateSessionToken();
        const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

        await Session.create({
            userId: user._id,
            tokenHash,
            expiresAt,
            userAgent: req.headers['user-agent'] || '',
            ipAddress: req.ip || ''
        });

        res.json({
            token: rawToken,
            user: {
                id: user._id,
                name: user.name,
                email: user.email,
                role: user.role,
                assignedDesignerId: user.assignedDesignerId
            }
        });
    } catch (error) {
        console.error("LOGIN ERROR:", error);
        res.status(500).json({ message: 'Server error' });
    }
});

// GET /api/auth/me - Retrieves current user through MongoDB session
router.get('/me', protect, async (req, res) => {
    res.json({
        id: req.user._id,
        name: req.user.name,
        email: req.user.email,
        role: req.user.role,
        assignedDesignerId: req.user.assignedDesignerId
    });
});

// POST /api/auth/logout - Deletes session document from MongoDB sessions collection
router.post('/logout', async (req, res) => {
    try {
        let token;
        if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
            token = req.headers.authorization.split(' ')[1];
        }

        if (token) {
            const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
            await Session.deleteOne({ tokenHash });
        }

        res.json({ message: 'Logged out successfully' });
    } catch (error) {
        res.status(500).json({ message: 'Logout error' });
    }
});

module.exports = router;