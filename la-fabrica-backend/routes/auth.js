const express = require('express');
const crypto = require('crypto');
const mongoose = require('mongoose');
const rateLimit = require('express-rate-limit');
const User = require('../models/User');
const Session = require('../models/Session');
const Invitation = require('../models/Invitation');
const { protect, authorize } = require('../middleware/authMiddleware');

const router = express.Router();

// Rate limiting for auth endpoints (disabled in test suite)
const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 20,
    standardHeaders: true,
    legacyHeaders: false,
    skip: () => process.env.NODE_ENV === 'test',
    message: { message: 'Too many authentication attempts. Please try again after 15 minutes.' }
});

// Helper to generate random raw session token and SHA-256 hash
function generateSessionToken() {
    const rawToken = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
    return { rawToken, tokenHash };
}

// GET /api/auth/designers - List designer accounts (restricted to authenticated users)
router.get('/designers', protect, async (req, res) => {
    try {
        const designers = await User.find({ role: 'designer' }).select('name email _id');
        res.json(designers);
    } catch (error) {
        console.error("FETCH DESIGNERS ERROR:", error);
        res.status(500).json({ message: 'Server error fetching designers' });
    }
});

// POST /api/auth/invitations - Designer creates an invitation code for an inventory user
router.post('/invitations', authLimiter, protect, authorize('designer'), async (req, res) => {
    try {
        const { invitedEmail } = req.body;
        const normalizedInvitedEmail = invitedEmail ? invitedEmail.toLowerCase().trim() : null;

        // Generate high-entropy invite code (8 bytes = 16 hex chars e.g. INV-A1B2C3D4E5F60718)
        const code = `INV-${crypto.randomBytes(8).toString('hex').toUpperCase()}`;
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

        const invitation = await Invitation.create({
            code,
            designerId: req.user._id,
            invitedEmail: normalizedInvitedEmail,
            expiresAt
        });

        res.status(201).json({
            message: 'Invitation code created successfully',
            code: invitation.code,
            invitedEmail: invitation.invitedEmail,
            expiresAt: invitation.expiresAt
        });
    } catch (error) {
        console.error("CREATE INVITATION ERROR:", error.message || error);
        res.status(500).json({ message: 'Failed to create invitation code' });
    }
});

// GET /api/auth/invitations - Designer lists their generated invitations
router.get('/invitations', protect, authorize('designer'), async (req, res) => {
    try {
        const invitations = await Invitation.find({ designerId: req.user._id })
            .populate('usedBy', 'name email')
            .sort({ createdAt: -1 });
        res.json(invitations);
    } catch (error) {
        console.error("LIST INVITATIONS ERROR:", error.message || error);
        res.status(500).json({ message: 'Failed to fetch invitations' });
    }
});

// GET /api/auth/invitations/validate - Public validation of an invitation code before registration
router.get('/invitations/validate', authLimiter, async (req, res) => {
    try {
        const { code } = req.query;
        if (!code || typeof code !== 'string' || !code.trim()) {
            return res.status(400).json({ message: 'Invitation code is required' });
        }

        const invitation = await Invitation.findOne({ code: code.trim().toUpperCase() })
            .populate('designerId', 'name email');

        if (!invitation) {
            return res.status(404).json({ message: 'Invitation code not found' });
        }

        if (invitation.isUsed) {
            return res.status(400).json({ message: 'This invitation code has already been used' });
        }

        if (new Date(invitation.expiresAt).getTime() <= Date.now()) {
            return res.status(400).json({ message: 'This invitation code has expired' });
        }

        res.json({
            valid: true,
            designerName: invitation.designerId?.name || 'Designer',
            designerEmail: invitation.designerId?.email || '',
            invitedEmail: invitation.invitedEmail || null
        });
    } catch (error) {
        console.error("VALIDATE INVITATION ERROR:", error.message || error);
        res.status(500).json({ message: 'Error validating invitation code' });
    }
});

// POST /api/auth/register
router.post('/register', authLimiter, async (req, res) => {
    const { name, email, password, role = 'designer', inviteCode } = req.body;
    try {
        if (!name || typeof name !== 'string' || !name.trim()) {
            return res.status(400).json({ message: 'Name is required' });
        }
        if (name.trim().length > 70) {
            return res.status(400).json({ message: 'Name cannot exceed 70 characters' });
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!email || typeof email !== 'string' || !emailRegex.test(email.trim())) {
            return res.status(400).json({ message: 'A valid email address is required' });
        }

        if (!password || typeof password !== 'string' || password.length < 8) {
            return res.status(400).json({ message: 'Password must be at least 8 characters long' });
        }

        const normalizedEmail = email.toLowerCase().trim();
        const validRoles = ['designer', 'inventory'];
        if (!validRoles.includes(role)) {
            return res.status(400).json({ message: 'Invalid user role' });
        }

        const userExists = await User.findOne({ email: normalizedEmail });
        if (userExists) {
            return res.status(409).json({ message: 'User with this email already exists' });
        }

        let assignedDesigner = null;
        let claimedInvitation = null;

        if (role === 'inventory') {
            if (!inviteCode || typeof inviteCode !== 'string' || !inviteCode.trim()) {
                return res.status(400).json({ 
                    message: 'An invitation code from an authorized designer is required to register an inventory account' 
                });
            }

            const cleanCode = inviteCode.trim().toUpperCase();
            const existingInvite = await Invitation.findOne({ code: cleanCode });

            if (!existingInvite) {
                return res.status(400).json({ message: 'Invalid invitation code' });
            }

            if (existingInvite.isUsed) {
                return res.status(400).json({ message: 'This invitation code has already been used' });
            }

            if (new Date(existingInvite.expiresAt).getTime() <= Date.now()) {
                return res.status(400).json({ message: 'This invitation code has expired' });
            }

            if (existingInvite.invitedEmail && existingInvite.invitedEmail !== normalizedEmail) {
                return res.status(400).json({ 
                    message: `This invitation code was issued for ${existingInvite.invitedEmail}` 
                });
            }

            // Verify designer account still exists
            const designerUser = await User.findOne({ _id: existingInvite.designerId, role: 'designer' });
            if (!designerUser) {
                return res.status(400).json({ message: 'Inviting designer account is no longer active' });
            }

            assignedDesigner = designerUser._id;

            // Atomically claim the invitation to guarantee single-use under concurrent requests
            claimedInvitation = await Invitation.findOneAndUpdate(
                {
                    _id: existingInvite._id,
                    isUsed: false,
                    expiresAt: { $gt: new Date() }
                },
                {
                    $set: {
                        isUsed: true,
                        usedAt: new Date()
                    }
                },
                { returnDocument: 'after' }
            );

            if (!claimedInvitation) {
                return res.status(400).json({ message: 'This invitation code has already been used or redeemed by another request' });
            }
        }

        // Coordinate registration and invitation finalization with MongoDB transaction where supported,
        // and deliberate compensating rollback where transactions are unsupported or on failure
        let session = null;
        let useTransaction = false;

        try {
            const topology = mongoose.connection?.client?.topology;
            const topType = topology?.description?.type;
            if (topType === 'ReplicaSetWithPrimary' || topType === 'Sharded') {
                session = await mongoose.startSession();
                session.startTransaction();
                useTransaction = true;
            }
        } catch (_) {
            session = null;
            useTransaction = false;
        }

        let user = null;
        try {
            const sessionOpt = useTransaction ? { session } : {};
            const createdUsers = await User.create([{
                name: name.trim(),
                email: normalizedEmail,
                passwordHash: password,
                role,
                assignedDesignerId: assignedDesigner
            }], sessionOpt);
            user = createdUsers[0];

            if (claimedInvitation) {
                await Invitation.updateOne(
                    { _id: claimedInvitation._id },
                    { $set: { usedBy: user._id } },
                    sessionOpt
                );
            }

            if (useTransaction && session) {
                await session.commitTransaction();
            }
        } catch (createErr) {
            if (useTransaction && session && session.inTransaction()) {
                try {
                    await session.abortTransaction();
                } catch (_) {}
            }
            // Compensating rollback: delete user if created, restore claimed invitation
            if (user && user._id) {
                await User.deleteOne({ _id: user._id }).catch(() => {});
            }
            if (claimedInvitation && claimedInvitation._id) {
                await Invitation.updateOne(
                    { _id: claimedInvitation._id },
                    { $set: { isUsed: false, usedBy: null, usedAt: null } }
                ).catch(() => {});
            }
            throw createErr;
        } finally {
            if (session) {
                session.endSession();
            }
        }

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
        console.error("REGISTER ERROR:", error.message || error);
        if (error.code === 11000 || (error.name === 'MongoServerError' && error.code === 11000)) {
            return res.status(409).json({ message: 'User with this email already exists' });
        }
        res.status(500).json({ message: 'Registration failed due to a server error' });
    }
});

// POST /api/auth/login
router.post('/login', authLimiter, async (req, res) => {
    const { email, password, expectedRole } = req.body;
    try {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!email || typeof email !== 'string' || !emailRegex.test(email.trim()) || !password || typeof password !== 'string' || password.length < 8) {
            return res.status(400).json({ message: 'Please provide a valid email and password (minimum 8 characters)' });
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
        console.error("LOGIN ERROR:", error.message || error);
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
        const authorization = req.headers.authorization || '';
        const [scheme, token] = authorization.trim().split(/\s+/);

        if (scheme?.toLowerCase() === 'bearer' && token) {
            const tokenHash = crypto.createHash('sha256').update(token.trim()).digest('hex');
            await Session.deleteOne({ tokenHash });
        }

        res.json({ message: 'Logged out successfully' });
    } catch (error) {
        res.status(500).json({ message: 'Logout error' });
    }
});

module.exports = router;