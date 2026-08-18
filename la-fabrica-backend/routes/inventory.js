const express = require('express');
const Inventory = require('../models/Inventory');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

// Get all inventory for user
router.get('/', protect, async (req, res) => {
    const items = await Inventory.find({ user: req.user._id }).populate('design', 'name');
    res.json(items);
});

// Update stock or price (FR-19, FR-22)
router.put('/:id', protect, async (req, res) => {
    const { stockQuantity, unitPrice } = req.body;
    const item = await Inventory.findById(req.params.id);
    if (!item) return res.status(404).json({ message: 'Item not found' });

    if (stockQuantity !== undefined) item.stockQuantity = stockQuantity;
    if (unitPrice !== undefined) item.unitPrice = unitPrice;
    
    const updatedItem = await item.save();
    res.json(updatedItem);
});

// Dashboard Summary (FR-11)
router.get('/dashboard', protect, async (req, res) => {
    const items = await Inventory.find({ user: req.user._id });
    
    const totalProducts = items.length;
    const availableStock = items.reduce((acc, item) => acc + item.stockQuantity, 0);
    const lowStockItems = items.filter(item => item.stockQuantity < 5).length; // Threshold: 5
    const totalInventoryValue = items.reduce((acc, item) => acc + (item.stockQuantity * item.unitPrice), 0);

    res.json({
        totalProducts,
        availableStock,
        lowStockItems,
        totalInventoryValue
    });
});

module.exports = router;