const mongoose = require('mongoose');

const inventorySchema = new mongoose.Schema({
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    design: { type: mongoose.Schema.Types.ObjectId, ref: 'Design' },
    productName: { type: String, required: true },
    stockQuantity: { 
        type: Number, 
        required: true, 
        min: [0, 'Stock quantity cannot be negative'] // Data Integrity
    },
    unitPrice: { 
        type: Number, 
        required: true, 
        min: [0, 'Unit price cannot be negative'] // Data Integrity
    }
}, { timestamps: true });

module.exports = mongoose.model('Inventory', inventorySchema);