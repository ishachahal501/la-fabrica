const mongoose = require('mongoose');

const designSchema = new mongoose.Schema({
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    name: { type: String, required: true },
    template: { type: String, default: 'tshirt' }, // tshirt, hoodie, etc.
    designData: { type: String }, // JSON string of canvas elements
    linkedInventory: { type: mongoose.Schema.Types.ObjectId, ref: 'Inventory' }
}, { timestamps: true });

module.exports = mongoose.model('Design', designSchema);