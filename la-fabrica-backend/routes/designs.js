const express = require('express');
const Design = require('../models/Design');
const Inventory = require('../models/Inventory');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

router.route('/')
    .get(protect, async (req, res) => {
        const designs = await Design.find({ user: req.user._id });
        res.json(designs);
    })
    .post(protect, async (req, res) => {
        const { name, template, designData } = req.body;
        const design = await Design.create({
            user: req.user._id, name, template, designData
        });
        res.status(201).json(design);
    });

router.route('/:id')
    .get(protect, async (req, res) => {
        const design = await Design.findById(req.params.id);
        if (!design) return res.status(404).json({ message: 'Design not found' });
        res.json(design);
    })
    .put(protect, async (req, res) => {
        const design = await Design.findById(req.params.id);
        if (design.user.toString() !== req.user._id.toString()) {
            return res.status(401).json({ message: 'Not authorized' });
        }
        design.name = req.body.name || design.name;
        design.designData = req.body.designData || design.designData;
        const updatedDesign = await design.save();
        res.json(updatedDesign);
    });

// Link design to inventory (FR-06)
router.post('/:id/link-inventory', protect, async (req, res) => {
    const { stockQuantity, unitPrice } = req.body;
    const design = await Design.findById(req.params.id);
    
    const inventory = await Inventory.create({
        user: req.user._id,
        design: design._id,
        productName: design.name,
        stockQuantity,
        unitPrice
    });

    design.linkedInventory = inventory._id;
    await design.save();
    res.status(201).json({ design, inventory });
});

module.exports = router;