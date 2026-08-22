const express = require('express');
const Inventory = require('../models/Inventory');
const Design = require('../models/Design');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

router.use(protect);

// Helper function to resolve targeted designerId for req.user
const getTargetDesignerId = (user) => {
    if (user.role === 'designer') return user._id;
    if (user.role === 'inventory') return user.assignedDesignerId;
    return null;
};

// GET all inventory items for authenticated user / assigned designer
router.get('/', async (req, res) => {
    try {
        const designerId = getTargetDesignerId(req.user);
        if (!designerId) {
            return res.json([]);
        }

        const items = await Inventory.find({ designerId })
            .populate('designId', 'name apparelType previewImage')
            .sort({ updatedAt: -1 });

        // Map items to standard output
        const formatted = items.map(item => ({
            _id: item._id,
            designerId: item.designerId,
            designId: item.designId?._id || item.designId,
            productName: item.productName || item.designId?.name || 'Apparel Item',
            apparelType: item.designId?.apparelType || 'T-Shirt',
            stockQuantity: item.stockQuantity,
            unitPrice: item.unitPrice,
            totalValue: item.stockQuantity * item.unitPrice,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        }));

        res.json(formatted);
    } catch (error) {
        console.error("GET INVENTORY ERROR:", error);
        res.status(500).json({ message: 'Error fetching inventory' });
    }
});

// GET single inventory item by ID
router.get('/:id', async (req, res) => {
    try {
        const item = await Inventory.findById(req.params.id).populate('designId', 'name apparelType');
        if (!item) return res.status(404).json({ message: 'Inventory item not found' });

        const targetDesignerId = getTargetDesignerId(req.user);
        if (!targetDesignerId || item.designerId.toString() !== targetDesignerId.toString()) {
            return res.status(403).json({ message: 'Forbidden: You are not authorized to view this inventory item' });
        }

        res.json({
            _id: item._id,
            designerId: item.designerId,
            designId: item.designId?._id || item.designId,
            productName: item.productName || item.designId?.name || 'Apparel Item',
            apparelType: item.designId?.apparelType || 'T-Shirt',
            stockQuantity: item.stockQuantity,
            unitPrice: item.unitPrice,
            totalValue: item.stockQuantity * item.unitPrice,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        });
    } catch (error) {
        res.status(500).json({ message: 'Error fetching inventory item' });
    }
});

// PUT update stock quantity or unit price
router.put('/:id', async (req, res) => {
    try {
        const { stockQuantity, unitPrice, action, quantity } = req.body;
        const item = await Inventory.findById(req.params.id);
        if (!item) return res.status(404).json({ message: 'Inventory item not found' });

        const targetDesignerId = getTargetDesignerId(req.user);
        if (!targetDesignerId || item.designerId.toString() !== targetDesignerId.toString()) {
            return res.status(403).json({ message: 'Forbidden: You are not authorized to modify this inventory item' });
        }

        if (action === 'add' && quantity !== undefined) {
            item.stockQuantity += Number(quantity);
        } else if (action === 'reduce' && quantity !== undefined) {
            item.stockQuantity = Math.max(0, item.stockQuantity - Number(quantity));
        } else {
            if (stockQuantity !== undefined) item.stockQuantity = Math.max(0, Number(stockQuantity));
            if (unitPrice !== undefined) item.unitPrice = Math.max(0, Number(unitPrice));
        }

        const updatedItem = await item.save();
        res.json({
            _id: updatedItem._id,
            designerId: updatedItem.designerId,
            designId: updatedItem.designId,
            productName: updatedItem.productName,
            stockQuantity: updatedItem.stockQuantity,
            unitPrice: updatedItem.unitPrice,
            totalValue: updatedItem.stockQuantity * updatedItem.unitPrice,
            updatedAt: updatedItem.updatedAt
        });
    } catch (error) {
        res.status(500).json({ message: 'Error updating inventory' });
    }
});

// GET Dashboard summary stats
router.get('/dashboard/summary', async (req, res) => {
    try {
        const designerId = getTargetDesignerId(req.user);
        if (!designerId) {
            return res.json({ totalProducts: 0, availableStock: 0, lowStockItems: 0, totalInventoryValue: 0 });
        }

        const items = await Inventory.find({ designerId });
        
        const totalProducts = items.length;
        const availableStock = items.reduce((acc, item) => acc + item.stockQuantity, 0);
        const lowStockItems = items.filter(item => item.stockQuantity < 10).length;
        const totalInventoryValue = items.reduce((acc, item) => acc + (item.stockQuantity * item.unitPrice), 0);

        res.json({
            totalProducts,
            availableStock,
            lowStockItems,
            totalInventoryValue
        });
    } catch (error) {
        res.status(500).json({ message: 'Error fetching summary' });
    }
});

module.exports = router;