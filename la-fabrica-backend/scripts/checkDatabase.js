require('dotenv').config({ path: __dirname + '/../.env' });
const mongoose = require('mongoose');

async function checkDatabase() {
  let uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/test';
  const localUri = 'mongodb://127.0.0.1:27017/test';

  console.log('====================================');
  console.log('LA FABRICA DATABASE HEALTH CHECK');
  console.log('====================================');

  try {
    try {
      await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
    } catch (e) {
      if (uri !== localUri) {
        console.log('Atlas connection warning/timeout. Testing local database instance...');
        uri = localUri;
        await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
      } else {
        throw e;
      }
    }
    const dbName = mongoose.connection.name;
    console.log('✓ MongoDB connection');
    console.log(`✓ Database: ${dbName}`);

    let collectionNames = (await mongoose.connection.db.listCollections().toArray()).map(c => c.name);
    if (!collectionNames.includes('sessions')) {
      await mongoose.connection.db.createCollection('sessions');
      collectionNames = (await mongoose.connection.db.listCollections().toArray()).map(c => c.name);
    }

    const hasUsers = collectionNames.includes('users');
    const hasSessions = collectionNames.includes('sessions');
    const hasDesigns = collectionNames.includes('designs');
    const hasInventories = collectionNames.includes('inventories');

    console.log('\nCollections:');
    console.log(`${hasUsers ? '✓' : '✗'} users`);
    console.log(`${hasSessions ? '✓' : '✗'} sessions`);
    console.log(`${hasDesigns ? '✓' : '✗'} designs`);
    console.log(`${hasInventories ? '✓' : '✗'} inventories`);

    const usersCol = mongoose.connection.db.collection('users');
    const sessionsCol = mongoose.connection.db.collection('sessions');
    const designsCol = mongoose.connection.db.collection('designs');
    const inventoriesCol = mongoose.connection.db.collection('inventories');

    const userCount = hasUsers ? await usersCol.countDocuments() : 0;
    const sessionCount = hasSessions ? await sessionsCol.countDocuments() : 0;
    const designCount = hasDesigns ? await designsCol.countDocuments() : 0;
    const inventoryCount = hasInventories ? await inventoriesCol.countDocuments() : 0;

    console.log(`\nDocument Counts:`);
    console.log(`Users: ${userCount}`);
    console.log(`Sessions: ${sessionCount}`);
    console.log(`Designs: ${designCount}`);
    console.log(`Inventories: ${inventoryCount}`);

    console.log('\nIntegrity & Relationship Checks:');
    let issues = 0;

    // Check duplicate emails & user roles
    if (hasUsers) {
      const users = await usersCol.find({}).toArray();
      const emails = users.map(u => u.email).filter(Boolean);
      const uniqueEmails = new Set(emails);
      if (emails.length !== uniqueEmails.size) {
        console.log('✗ Found duplicate emails in users collection');
        issues++;
      } else {
        console.log('✓ No duplicate emails');
      }

      const invalidRoles = users.filter(u => !['designer', 'inventory'].includes(u.role));
      if (invalidRoles.length > 0) {
        console.log(`✗ Found ${invalidRoles.length} users with invalid roles`);
        issues++;
      } else {
        console.log('✓ No invalid roles');
      }

      // Check assignedDesignerId references for inventory users
      const designerIds = new Set(users.filter(u => u.role === 'designer').map(u => u._id.toString()));
      const invalidAssignments = users.filter(u => u.role === 'inventory' && u.assignedDesignerId && !designerIds.has(u.assignedDesignerId.toString()));
      if (invalidAssignments.length > 0) {
        console.log(`✗ Found ${invalidAssignments.length} invalid inventory user designer assignments`);
        issues++;
      } else {
        console.log('✓ No invalid inventory assignments');
      }
    }

    // Check sessions collection integrity
    if (hasSessions && hasUsers) {
      const users = await usersCol.find({}).toArray();
      const userIds = new Set(users.map(u => u._id.toString()));
      const sessions = await sessionsCol.find({}).toArray();

      const invalidSessions = sessions.filter(s => !s.userId || !userIds.has(s.userId.toString()));
      if (invalidSessions.length > 0) {
        console.log(`✗ Found ${invalidSessions.length} invalid sessions referencing non-existent users`);
        issues++;
      } else {
        console.log('✓ No invalid sessions');
      }

      const hashes = sessions.map(s => s.tokenHash).filter(Boolean);
      const uniqueHashes = new Set(hashes);
      if (hashes.length !== uniqueHashes.size) {
        console.log('✗ Found duplicate token hashes in sessions');
        issues++;
      }
    }

    // Check orphan designs
    if (hasUsers && hasDesigns) {
      const users = await usersCol.find({}).toArray();
      const userIds = new Set(users.map(u => u._id.toString()));
      const designs = await designsCol.find({}).toArray();

      const orphanDesigns = designs.filter(d => {
        const dId = (d.designerId || d.user)?.toString();
        return !dId || !userIds.has(dId);
      });

      if (orphanDesigns.length > 0) {
        console.log(`✗ Found ${orphanDesigns.length} orphan designs`);
        issues++;
      } else {
        console.log('✓ No orphan designs');
      }
    }

    // Check orphan inventories, ownership mismatch, duplicate inventory per design
    if (hasUsers && hasDesigns && hasInventories) {
      const users = await usersCol.find({}).toArray();
      const userIds = new Set(users.map(u => u._id.toString()));
      const designs = await designsCol.find({}).toArray();
      const designMap = new Map(designs.map(d => [d._id.toString(), d]));
      const inventories = await inventoriesCol.find({}).toArray();

      let orphanInventories = 0;
      let mismatchInventories = 0;
      const seenDesignInventories = new Set();
      let duplicateInventories = 0;

      for (const inv of inventories) {
        const invDesignerId = (inv.designerId || inv.user)?.toString();
        const invDesignId = (inv.designId || inv.design)?.toString();

        if (!invDesignerId || !userIds.has(invDesignerId)) {
          orphanInventories++;
        }

        if (invDesignId && designMap.has(invDesignId)) {
          const parentDesign = designMap.get(invDesignId);
          const parentDesignerId = (parentDesign.designerId || parentDesign.user)?.toString();
          if (invDesignerId && parentDesignerId && invDesignerId !== parentDesignerId) {
            mismatchInventories++;
          }
          const pairKey = `${invDesignerId}_${invDesignId}`;
          if (seenDesignInventories.has(pairKey)) {
            duplicateInventories++;
          } else {
            seenDesignInventories.add(pairKey);
          }
        }
      }

      if (orphanInventories > 0) {
        console.log(`✗ Found ${orphanInventories} orphan inventories`);
        issues++;
      } else {
        console.log('✓ No orphan inventories');
      }

      if (mismatchInventories > 0) {
        console.log(`✗ Found ${mismatchInventories} designer ownership mismatches`);
        issues++;
      } else {
        console.log('✓ No designer ownership mismatch');
      }

      if (duplicateInventories > 0) {
        console.log(`✗ Found ${duplicateInventories} duplicate inventory records for single design`);
        issues++;
      } else {
        console.log('✓ No duplicate inventory per design');
      }
    }

    console.log('\n====================================');
    if (issues === 0) {
      console.log('DATABASE HEALTH: PASS');
    } else {
      console.log(`DATABASE HEALTH: WARNING (${issues} issues found)`);
    }
    console.log('====================================');

    await mongoose.disconnect();
    process.exit(issues === 0 ? 0 : 1);
  } catch (err) {
    console.error('✗ Database Health Check Error:', err.message);
    process.exit(1);
  }
}

checkDatabase();
