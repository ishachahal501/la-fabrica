const mongoose = require('mongoose');

const invitationSchema = new mongoose.Schema({
    code: { 
        type: String, 
        required: true, 
        unique: true, 
        uppercase: true, 
        trim: true,
        index: true 
    },
    designerId: { 
        type: mongoose.Schema.Types.ObjectId, 
        ref: 'User', 
        required: true, 
        index: true 
    },
    invitedEmail: { 
        type: String, 
        lowercase: true, 
        trim: true 
    },
    isUsed: { 
        type: Boolean, 
        default: false, 
        index: true 
    },
    usedBy: { 
        type: mongoose.Schema.Types.ObjectId, 
        ref: 'User' 
    },
    usedAt: { 
        type: Date 
    },
    expiresAt: { 
        type: Date, 
        required: true
    }
}, { timestamps: true });

// Auto-expire invitation after expiresAt date
invitationSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('Invitation', invitationSchema, 'invitations');
