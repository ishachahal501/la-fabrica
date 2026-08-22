const express = require('express');
const Design = require('../models/Design');
const Inventory = require('../models/Inventory');
const { protect, authorize } = require('../middleware/authMiddleware');

const router = express.Router();

router.use(protect);
router.use(authorize('designer'));

// GET all designs owned by logged-in designer
router.get('/', async (req, res) => {
    try {
        const designs = await Design.find({ designerId: req.user._id }).sort({ updatedAt: -1 });
        res.json(designs);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching designs' });
    }
});

// POST create new design
router.post('/', async (req, res) => {
    const { name, apparelType = 'tshirt', template, previewImage = '', designData = '{}', initialStock = 50, unitPrice = 700 } = req.body;
    try {
        if (!name) {
            return res.status(400).json({ message: 'Design name is required' });
        }

        const type = apparelType || template || 'tshirt';
        const design = await Design.create({
            designerId: req.user._id,
            name,
            apparelType: type,
            previewImage,
            designData
        });

        // Automatically create associated inventory item
        const inventory = await Inventory.create({
            designerId: req.user._id,
            designId: design._id,
            productName: design.name,
            stockQuantity: Number(initialStock) || 0,
            unitPrice: Number(unitPrice) || 0
        });

        design.linkedInventory = inventory._id;
        await design.save();

        res.status(201).json({ design, inventory });
    } catch (error) {
        console.error("CREATE DESIGN ERROR:", error);
        res.status(500).json({ message: 'Error creating design', error: error.message });
    }
});

// GET single design
router.get('/:id', async (req, res) => {
    try {
        const design = await Design.findById(req.params.id);
        if (!design) return res.status(404).json({ message: 'Design not found' });

        if (design.designerId.toString() !== req.user._id.toString()) {
            return res.status(403).json({ message: 'Forbidden: You do not own this design' });
        }

        res.json(design);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching design' });
    }
});

// PUT update design
router.put('/:id', async (req, res) => {
    try {
        const design = await Design.findById(req.params.id);
        if (!design) return res.status(404).json({ message: 'Design not found' });

        if (design.designerId.toString() !== req.user._id.toString()) {
            return res.status(403).json({ message: 'Forbidden: You do not own this design' });
        }

        if (req.body.name) design.name = req.body.name;
        if (req.body.apparelType) design.apparelType = req.body.apparelType;
        if (req.body.previewImage !== undefined) design.previewImage = req.body.previewImage;
        if (req.body.designData !== undefined) design.designData = req.body.designData;

        const updatedDesign = await design.save();
        res.json(updatedDesign);
    } catch (error) {
        res.status(500).json({ message: 'Error updating design' });
    }
});

// DELETE design
router.delete('/:id', async (req, res) => {
    try {
        const design = await Design.findById(req.params.id);
        if (!design) return res.status(404).json({ message: 'Design not found' });

        if (design.designerId.toString() !== req.user._id.toString()) {
            return res.status(403).json({ message: 'Forbidden: You do not own this design' });
        }

        await Inventory.deleteMany({ designId: design._id });
        await design.deleteOne();
        res.json({ message: 'Design and associated inventory deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: 'Error deleting design' });
    }
});

module.exports = router;