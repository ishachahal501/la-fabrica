const express = require('express');
const mongoose = require('mongoose');
const Design = require('../models/Design');
const Inventory = require('../models/Inventory');
const { protect, authorize } = require('../middleware/authMiddleware');

const router = express.Router();

router.use(protect);
router.use(authorize('designer'));

// Helper to validate and sanitize design payload
function validateDesignPayload(body, isCreate = false) {
    const { name, apparelType, previewImage, designData, initialStock, unitPrice } = body;

    if (isCreate || name !== undefined) {
        if (!name || typeof name !== 'string' || !name.trim()) {
            return 'Design name is required';
        }
        if (name.trim().length > 100) {
            return 'Design name cannot exceed 100 characters';
        }
    }

    if (apparelType !== undefined) {
        const validTypes = ['tshirt', 'hoodie', 'sweatshirt', 'tank', 'polo'];
        if (typeof apparelType !== 'string' || !validTypes.includes(apparelType.toLowerCase())) {
            return 'Invalid apparel type. Allowed types: tshirt, hoodie, sweatshirt, tank, polo';
        }
    }

    if (previewImage !== undefined && previewImage !== '') {
        if (typeof previewImage !== 'string') {
            return 'previewImage must be a string';
        }
        if (previewImage.length > 2 * 1024 * 1024) {
            return 'previewImage payload exceeds maximum allowed size of 2MB';
        }
        const isDataUri = previewImage.startsWith('data:image/');
        const isUrl = previewImage.startsWith('http://') || previewImage.startsWith('https://');
        if (!isDataUri && !isUrl) {
            return 'previewImage must be a valid image data URI or URL';
        }
    }

    if (designData !== undefined && designData !== '') {
        if (typeof designData !== 'string') {
            return 'designData must be a valid JSON string';
        }
        if (designData.length > 2 * 1024 * 1024) {
            return 'designData exceeds maximum allowed size of 2MB';
        }
        try {
            JSON.parse(designData);
        } catch (_) {
            return 'designData contains malformed JSON';
        }
    }

    // Total payload validation across combined fields
    const previewLength = typeof previewImage === 'string' ? previewImage.length : 0;
    const designDataLength = typeof designData === 'string' ? designData.length : 0;
    if (previewLength + designDataLength > 4 * 1024 * 1024) {
        return 'Combined design payload (previewImage + designData) exceeds maximum allowed size of 4MB';
    }

    if (initialStock !== undefined) {
        const stockNum = Number(initialStock);
        if (!Number.isInteger(stockNum) || stockNum < 0) {
            return 'initialStock must be a non-negative integer';
        }
    }

    if (unitPrice !== undefined) {
        const priceNum = Number(unitPrice);
        if (!Number.isFinite(priceNum) || priceNum < 0) {
            return 'unitPrice must be a non-negative finite number';
        }
    }

    return null;
}

// GET all designs owned by logged-in designer
router.get('/', async (req, res) => {
    try {
        const designs = await Design.find({ designerId: req.user._id }).sort({ updatedAt: -1 });
        res.json(designs);
    } catch (error) {
        console.error("FETCH DESIGNS ERROR:", error);
        res.status(500).json({ message: 'Error fetching designs' });
    }
});

// POST create new design (Atomic creation of Design and linked Inventory)
router.post('/', async (req, res) => {
    const validationError = validateDesignPayload(req.body, true);
    if (validationError) {
        return res.status(400).json({ message: validationError });
    }

    const { name, apparelType = 'tshirt', template, previewImage = '', designData = '{}', initialStock = 50, unitPrice = 700 } = req.body;
    const stockNum = Number(initialStock !== undefined ? initialStock : 50);
    const priceNum = Number(unitPrice !== undefined ? unitPrice : 700);

    let session = null;
    let useTransaction = false;

    try {
        const topology = mongoose.connection?.client?.topology;
        const topType = topology?.description?.type;
        if (topType === 'ReplicaSetWithPrimary' || topType === 'Sharded') {
            session = await mongoose.startSession();
            session.startTransaction();
            useTransaction = true;
        }
    } catch (_) {
        session = null;
        useTransaction = false;
    }

    let createdDesign = null;
    let createdInventory = null;

    try {
        const sessionOpt = useTransaction ? { session } : {};
        const type = apparelType || template || 'tshirt';

        const designDocs = await Design.create([{
            designerId: req.user._id,
            name: name.trim(),
            apparelType: type,
            previewImage,
            designData
        }], sessionOpt);
        createdDesign = designDocs[0];

        // Automatically create associated inventory item
        const inventoryDocs = await Inventory.create([{
            designerId: req.user._id,
            designId: createdDesign._id,
            productName: createdDesign.name,
            stockQuantity: stockNum,
            unitPrice: priceNum
        }], sessionOpt);
        createdInventory = inventoryDocs[0];

        createdDesign.linkedInventory = createdInventory._id;
        await createdDesign.save(sessionOpt);

        if (useTransaction) {
            await session.commitTransaction();
        }

        res.status(201).json({ design: createdDesign, inventory: createdInventory });
    } catch (error) {
        if (useTransaction && session && session.inTransaction()) {
            try {
                await session.abortTransaction();
            } catch (_) {}
        }
        // Deliberate compensating rollback to guarantee no orphan documents or broken invariant
        if (createdInventory && createdInventory._id) {
            await Inventory.deleteOne({ _id: createdInventory._id }).catch(() => {});
        }
        if (createdDesign && createdDesign._id) {
            await Design.deleteOne({ _id: createdDesign._id }).catch(() => {});
        }
        console.error("CREATE DESIGN ERROR:", error.message || error);
        res.status(500).json({ message: 'Error creating design and inventory' });
    } finally {
        if (session) {
            session.endSession();
        }
    }
});

// GET single design (Scoped by logged-in designer ownership)
router.get('/:id', async (req, res) => {
    try {
        if (!mongoose.isValidObjectId(req.params.id)) {
            return res.status(400).json({ message: 'Invalid design ID format' });
        }

        const design = await Design.findById(req.params.id);
        if (!design) return res.status(404).json({ message: 'Design not found' });

        if (design.designerId.toString() !== req.user._id.toString()) {
            return res.status(403).json({ message: 'Forbidden: You do not own this design' });
        }

        res.json(design);
    } catch (error) {
        if (error.name === 'CastError') {
            return res.status(400).json({ message: 'Invalid design ID format' });
        }
        console.error("GET DESIGN ERROR:", error);
        res.status(500).json({ message: 'Error fetching design' });
    }
});

// PUT update design (Scoped by logged-in designer ownership)
router.put('/:id', async (req, res) => {
    try {
        if (!mongoose.isValidObjectId(req.params.id)) {
            return res.status(400).json({ message: 'Invalid design ID format' });
        }

        const validationError = validateDesignPayload(req.body, false);
        if (validationError) {
            return res.status(400).json({ message: validationError });
        }

        const design = await Design.findById(req.params.id);
        if (!design) return res.status(404).json({ message: 'Design not found' });

        if (design.designerId.toString() !== req.user._id.toString()) {
            return res.status(403).json({ message: 'Forbidden: You do not own this design' });
        }

        if (req.body.name) design.name = req.body.name.trim();
        if (req.body.apparelType) design.apparelType = req.body.apparelType;
        if (req.body.previewImage !== undefined) design.previewImage = req.body.previewImage;
        if (req.body.designData !== undefined) design.designData = req.body.designData;

        const updatedDesign = await design.save();
        res.json(updatedDesign);
    } catch (error) {
        if (error.name === 'CastError') {
            return res.status(400).json({ message: 'Invalid design ID format' });
        }
        console.error("UPDATE DESIGN ERROR:", error);
        res.status(500).json({ message: 'Error updating design' });
    }
});

// DELETE design (Scoped by logged-in designer ownership)
router.delete('/:id', async (req, res) => {
    try {
        if (!mongoose.isValidObjectId(req.params.id)) {
            return res.status(400).json({ message: 'Invalid design ID format' });
        }

        const design = await Design.findById(req.params.id);
        if (!design) return res.status(404).json({ message: 'Design not found' });

        if (design.designerId.toString() !== req.user._id.toString()) {
            return res.status(403).json({ message: 'Forbidden: You do not own this design' });
        }

        await Inventory.deleteMany({ designId: design._id });
        await design.deleteOne();
        res.json({ message: 'Design and associated inventory deleted successfully' });
    } catch (error) {
        if (error.name === 'CastError') {
            return res.status(400).json({ message: 'Invalid design ID format' });
        }
        console.error("DELETE DESIGN ERROR:", error);
        res.status(500).json({ message: 'Error deleting design' });
    }
});

module.exports = router;