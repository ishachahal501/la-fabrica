const express = require('express');
const mongoose = require('mongoose');
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

// Helper function to format apparel type to human-readable label
function formatApparelLabel(type) {
    switch ((type || '').toLowerCase()) {
        case 'tshirt': return 'T-Shirt';
        case 'hoodie': return 'Hoodie';
        case 'sweatshirt': return 'Sweatshirt';
        case 'tank': return 'Tank Top';
        case 'polo': return 'Polo Shirt';
        default: return type || 'T-Shirt';
    }
}

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
            apparelType: item.designId?.apparelType || 'tshirt',
            apparelLabel: formatApparelLabel(item.designId?.apparelType),
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

// GET Dashboard summary stats via MongoDB aggregation pipeline
router.get('/dashboard/summary', async (req, res) => {
    try {
        const designerId = getTargetDesignerId(req.user);
        if (!designerId) {
            return res.json({ totalProducts: 0, availableStock: 0, lowStockItems: 0, totalInventoryValue: 0 });
        }

        const objectId = new mongoose.Types.ObjectId(designerId);
        const stats = await Inventory.aggregate([
            { $match: { designerId: objectId } },
            {
                $group: {
                    _id: null,
                    totalProducts: { $sum: 1 },
                    availableStock: { $sum: '$stockQuantity' },
                    lowStockItems: {
                        $sum: {
                            $cond: [{ $lt: ['$stockQuantity', 10] }, 1, 0]
                        }
                    },
                    totalInventoryValue: {
                        $sum: { $multiply: ['$stockQuantity', '$unitPrice'] }
                    }
                }
            }
        ]);

        const summary = stats.length > 0 ? {
            totalProducts: stats[0].totalProducts,
            availableStock: stats[0].availableStock,
            lowStockItems: stats[0].lowStockItems,
            totalInventoryValue: stats[0].totalInventoryValue
        } : {
            totalProducts: 0,
            availableStock: 0,
            lowStockItems: 0,
            totalInventoryValue: 0
        };

        res.json(summary);
    } catch (error) {
        console.error("GET DASHBOARD SUMMARY ERROR:", error);
        res.status(500).json({ message: 'Error fetching summary' });
    }
});

// GET single inventory item by ID
router.get('/:id', async (req, res) => {
    try {
        if (!mongoose.isValidObjectId(req.params.id)) {
            return res.status(400).json({ message: 'Invalid inventory ID format' });
        }

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
            apparelType: item.designId?.apparelType || 'tshirt',
            apparelLabel: formatApparelLabel(item.designId?.apparelType),
            stockQuantity: item.stockQuantity,
            unitPrice: item.unitPrice,
            totalValue: item.stockQuantity * item.unitPrice,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        });
    } catch (error) {
        if (error.name === 'CastError') {
            return res.status(400).json({ message: 'Invalid inventory ID format' });
        }
        console.error("GET INVENTORY ITEM ERROR:", error);
        res.status(500).json({ message: 'Error fetching inventory item' });
    }
});

// PUT update stock quantity or unit price with strict validation
router.put('/:id', async (req, res) => {
    try {
        if (!mongoose.isValidObjectId(req.params.id)) {
            return res.status(400).json({ message: 'Invalid inventory ID format' });
        }

        const { stockQuantity, unitPrice, action, quantity } = req.body;
        const item = await Inventory.findById(req.params.id);
        if (!item) return res.status(404).json({ message: 'Inventory item not found' });

        const targetDesignerId = getTargetDesignerId(req.user);
        if (!targetDesignerId || item.designerId.toString() !== targetDesignerId.toString()) {
            return res.status(403).json({ message: 'Forbidden: You are not authorized to modify this inventory item' });
        }

        // Validate action if specified
        if (action !== undefined) {
            if (action !== 'add' && action !== 'reduce') {
                return res.status(400).json({ message: 'Invalid action. Action must be "add" or "reduce"' });
            }
            if (quantity === undefined) {
                return res.status(400).json({ message: 'Quantity is required when action is specified' });
            }
            const numQty = Number(quantity);
            if (!Number.isInteger(numQty) || numQty <= 0) {
                return res.status(400).json({ message: 'Quantity must be a positive integer' });
            }

            if (action === 'add') {
                item.stockQuantity += numQty;
            } else if (action === 'reduce') {
                item.stockQuantity = Math.max(0, item.stockQuantity - numQty);
            }
        } else {
            if (stockQuantity !== undefined) {
                const numStock = Number(stockQuantity);
                if (!Number.isInteger(numStock) || numStock < 0) {
                    return res.status(400).json({ message: 'stockQuantity must be a non-negative integer' });
                }
                item.stockQuantity = numStock;
            }

            if (unitPrice !== undefined) {
                const numPrice = Number(unitPrice);
                if (!Number.isFinite(numPrice) || numPrice < 0) {
                    return res.status(400).json({ message: 'unitPrice must be a non-negative finite number' });
                }
                item.unitPrice = numPrice;
            }
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
        if (error.name === 'CastError') {
            return res.status(400).json({ message: 'Invalid inventory ID format' });
        }
        console.error("UPDATE INVENTORY ERROR:", error);
        res.status(500).json({ message: 'Error updating inventory' });
    }
});

module.exports = router;