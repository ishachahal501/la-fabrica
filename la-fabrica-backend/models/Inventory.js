const mongoose = require('mongoose');

const inventorySchema = new mongoose.Schema({
    designerId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    designId: { type: mongoose.Schema.Types.ObjectId, ref: 'Design', required: true, index: true },
    productName: { type: String },
    stockQuantity: { 
        type: Number, 
        required: true, 
        min: [0, 'Stock quantity cannot be negative']
    },
    unitPrice: { 
        type: Number, 
        required: true, 
        min: [0, 'Unit price cannot be negative']
    },
    lowStockThreshold: {
        type: Number,
        default: 15,
        min: [1, 'Low stock threshold must be at least 1']
    },
    recentChanges: [{
        action: { type: String, enum: ['add', 'reduce', 'set', 'initial'], default: 'set' },
        quantity: { type: Number, required: true },
        previousStock: { type: Number, required: true },
        newStock: { type: Number, required: true },
        note: { type: String, default: '' },
        timestamp: { type: Date, default: Date.now }
    }]
}, { timestamps: true });

// Compound unique index ensuring ONE inventory record per designer + design
inventorySchema.index({ designerId: 1, designId: 1 }, { unique: true });

// Virtual aliases for compatibility
inventorySchema.virtual('user').get(function() {
    return this.designerId;
});
inventorySchema.virtual('design').get(function() {
    return this.designId;
});

module.exports = mongoose.model('Inventory', inventorySchema, 'inventories');