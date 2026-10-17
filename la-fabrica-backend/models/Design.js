const mongoose = require('mongoose');

const designSchema = new mongoose.Schema({
    designerId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    name: { type: String, required: true },
    apparelType: { 
        type: String, 
        enum: ['tshirt', 'hoodie', 'sweatshirt', 'tank', 'polo'], 
        default: 'tshirt' 
    },
    previewImage: { type: String, default: '' },
    designData: { type: String, default: '{}' },
    linkedInventory: { type: mongoose.Schema.Types.ObjectId, ref: 'Inventory' }
}, { timestamps: true });

// Alias user to designerId for backwards compatibility
designSchema.virtual('user').get(function() {
    return this.designerId;
});

module.exports = mongoose.model('Design', designSchema, 'designs');