require('dotenv').config({ path: __dirname + '/../.env' });
const mongoose = require('mongoose');

function redactUri(uri) {
  try {
    return uri.replace(
      /mongodb(\+srv)?:\/\/([^:]+):([^@]+)@/,
      'mongodb$1://$2:****@'
    );
  } catch (_) {
    return '[REDACTED]';
  }
}

async function checkDatabase() {
  const uri =
    process.env.MONGO_URI ||
    'mongodb://127.0.0.1:27017/test';

  console.log('====================================');
  console.log('LA FABRICA DATABASE HEALTH CHECK');
  console.log(`Connecting: ${redactUri(uri)}`);
  console.log('====================================');

  let issues = 0;

  try {
    await mongoose.connect(uri, {
      serverSelectionTimeoutMS: 5000
    });

    const db = mongoose.connection.db;
    const dbName = mongoose.connection.name;

    console.log('✓ MongoDB connection');
    console.log(`✓ Database: ${dbName}`);

    let collectionNames = (
      await db.listCollections().toArray()
    ).map(collection => collection.name);

    if (!collectionNames.includes('sessions')) {
      await db.createCollection('sessions');
      collectionNames = (
        await db.listCollections().toArray()
      ).map(collection => collection.name);
    }

    const hasUsers = collectionNames.includes('users');
    const hasSessions = collectionNames.includes('sessions');
    const hasDesigns = collectionNames.includes('designs');
    const hasInventories = collectionNames.includes('inventories');
    const hasInvitations = collectionNames.includes('invitations');

    console.log('\nCollections:');
    console.log(`${hasUsers ? '✓' : '✗'} users`);
    console.log(`${hasSessions ? '✓' : '✗'} sessions`);
    console.log(`${hasDesigns ? '✓' : '✗'} designs`);
    console.log(`${hasInventories ? '✓' : '✗'} inventories`);

    const usersCol = db.collection('users');
    const sessionsCol = db.collection('sessions');
    const designsCol = db.collection('designs');
    const inventoriesCol = db.collection('inventories');

    const userCount = hasUsers
      ? await usersCol.countDocuments()
      : 0;
    const sessionCount = hasSessions
      ? await sessionsCol.countDocuments()
      : 0;
    const designCount = hasDesigns
      ? await designsCol.countDocuments()
      : 0;
    const inventoryCount = hasInventories
      ? await inventoriesCol.countDocuments()
      : 0;

    console.log('\nDocument Counts:');
    console.log(`Users: ${userCount}`);
    console.log(`Sessions: ${sessionCount}`);
    console.log(`Designs: ${designCount}`);
    console.log(`Inventories: ${inventoryCount}`);

    console.log('\nIntegrity & Relationship Checks:');

    // Check duplicate emails, roles, and inventory-user assignments.
    let users = [];

    if (hasUsers) {
      users = await usersCol.find({}).toArray();

      const emails = users
        .map(user => (
          typeof user.email === 'string'
            ? user.email.trim().toLowerCase()
            : null
        ))
        .filter(Boolean);

      const uniqueEmails = new Set(emails);

      if (emails.length !== uniqueEmails.size) {
        console.log('✗ Found duplicate emails in users collection');
        issues++;
      } else {
        console.log('✓ No duplicate emails');
      }

      const invalidRoles = users.filter(
        user => !['designer', 'inventory'].includes(user.role)
      );

      if (invalidRoles.length > 0) {
        console.log(
          `✗ Found ${invalidRoles.length} users with invalid roles`
        );
        issues++;
      } else {
        console.log('✓ No invalid roles');
      }

      const designerIds = new Set(
        users
          .filter(user => user.role === 'designer')
          .map(user => user._id.toString())
      );

      const invalidAssignments = users.filter(user =>
        user.role === 'inventory' &&
        user.assignedDesignerId &&
        !designerIds.has(user.assignedDesignerId.toString())
      );

      if (invalidAssignments.length > 0) {
        console.log(
          `✗ Found ${invalidAssignments.length} invalid inventory user designer assignments`
        );
        issues++;
      } else {
        console.log('✓ No invalid inventory assignments');
      }

      const unassignedInventoryUsers = users.filter(
        user =>
          user.role === 'inventory' &&
          !user.assignedDesignerId
      );

      if (unassignedInventoryUsers.length > 0) {
        console.log(
          `✗ Found ${unassignedInventoryUsers.length} inventory users without an assigned designer`
        );
        issues++;
      } else {
        console.log('✓ All inventory users have a designer assigned');
      }
    } else {
      console.log('✗ users collection is missing');
      issues++;
    }

    // Check session references and duplicate token hashes.
    if (hasSessions && hasUsers) {
      const userIds = new Set(
        users.map(user => user._id.toString())
      );

      const sessions = await sessionsCol.find({}).toArray();

      const invalidSessions = sessions.filter(
        session =>
          !session.userId ||
          !userIds.has(session.userId.toString())
      );

      if (invalidSessions.length > 0) {
        console.log(
          `✗ Found ${invalidSessions.length} invalid sessions referencing non-existent users`
        );
        issues++;
      } else {
        console.log('✓ No invalid sessions');
      }

      const now = new Date();
      const expiredSessions = sessions.filter(
        session =>
          session.expiresAt &&
          new Date(session.expiresAt) <= now
      );

      if (expiredSessions.length > 0) {
        console.log(
          `⚠ Found ${expiredSessions.length} expired sessions still stored`
        );
      }

      const hashes = sessions
        .map(session => session.tokenHash)
        .filter(Boolean);

      if (hashes.length !== new Set(hashes).size) {
        console.log('✗ Found duplicate token hashes in sessions');
        issues++;
      } else {
        console.log('✓ No duplicate session token hashes');
      }
    } else if (!hasSessions) {
      console.log('✗ sessions collection is missing');
      issues++;
    }

    // Check that every design references an existing user.
    let designs = [];

    if (hasDesigns) {
      designs = await designsCol.find({}).toArray();

      if (hasUsers) {
        const userIds = new Set(
          users.map(user => user._id.toString())
        );

        const orphanDesigns = designs.filter(design => {
          const designerId = (
            design.designerId ||
            design.user
          )?.toString();

          return !designerId || !userIds.has(designerId);
        });

        if (orphanDesigns.length > 0) {
          console.log(
            `✗ Found ${orphanDesigns.length} orphan designs`
          );
          issues++;
        } else {
          console.log('✓ No orphan designs');
        }
      }
    } else {
      console.log('✗ designs collection is missing');
      issues++;
    }

    // Check inventory references, ownership, and duplicates.
    if (hasInventories) {
      const inventories = await inventoriesCol.find({}).toArray();

      const userIds = new Set(
        users.map(user => user._id.toString())
      );

      const designMap = new Map(
        designs.map(design => [
          design._id.toString(),
          design
        ])
      );

      let orphanInventories = 0;
      let missingDesignRefs = 0;
      let mismatchInventories = 0;
      let duplicateInventories = 0;

      const seenDesignInventories = new Set();

      for (const inventory of inventories) {
        const inventoryDesignerId = (
          inventory.designerId ||
          inventory.user
        )?.toString();

        const inventoryDesignId = (
          inventory.designId ||
          inventory.design
        )?.toString();

        if (
          !inventoryDesignerId ||
          !userIds.has(inventoryDesignerId)
        ) {
          orphanInventories++;
        }

        if (
          !inventoryDesignId ||
          !designMap.has(inventoryDesignId)
        ) {
          missingDesignRefs++;
          continue;
        }

        const parentDesign = designMap.get(inventoryDesignId);

        const parentDesignerId = (
          parentDesign.designerId ||
          parentDesign.user
        )?.toString();

        if (
          inventoryDesignerId &&
          parentDesignerId &&
          inventoryDesignerId !== parentDesignerId
        ) {
          mismatchInventories++;
        }

        const pairKey =
          `${inventoryDesignerId}_${inventoryDesignId}`;

        if (seenDesignInventories.has(pairKey)) {
          duplicateInventories++;
        } else {
          seenDesignInventories.add(pairKey);
        }
      }

      if (orphanInventories > 0) {
        console.log(
          `✗ Found ${orphanInventories} orphan inventories`
        );
        issues++;
      } else {
        console.log('✓ No orphan inventories');
      }

      if (missingDesignRefs > 0) {
        console.log(
          `✗ Found ${missingDesignRefs} inventory records referencing missing designs`
        );
        issues++;
      } else {
        console.log('✓ No missing inventory-to-design references');
      }

      if (mismatchInventories > 0) {
        console.log(
          `✗ Found ${mismatchInventories} designer ownership mismatches`
        );
        issues++;
      } else {
        console.log('✓ No designer ownership mismatch');
      }

      if (duplicateInventories > 0) {
        console.log(
          `✗ Found ${duplicateInventories} duplicate inventory records for single design`
        );
        issues++;
      } else {
        console.log('✓ No duplicate inventory per design');
      }
    } else {
      console.log('✗ inventories collection is missing');
      issues++;
    }

    // Check invitation TTL index if the collection exists.
    if (hasInvitations) {
      const invitationIndexes = await db
        .collection('invitations')
        .indexes();

      const ttlIndex = invitationIndexes.find(
        index => index.key && index.key.expiresAt === 1
      );

      if (!ttlIndex) {
        console.log(
          '✗ Missing expiresAt index on invitations collection'
        );
        issues++;
      } else if (ttlIndex.expireAfterSeconds !== 0) {
        console.log(
          `✗ expiresAt index has expireAfterSeconds=${ttlIndex.expireAfterSeconds}; expected 0`
        );
        issues++;
      } else {
        console.log(
          '✓ Invitations MongoDB TTL index active'
        );
      }
    } else {
      console.log(
        '⚠ invitations collection not found; TTL index check skipped'
      );
    }

    console.log('\n====================================');

    if (issues === 0) {
      console.log('DATABASE HEALTH: PASS');
    } else {
      console.log(
        `DATABASE HEALTH: WARNING (${issues} issues found)`
      );
    }

    console.log('====================================');

    await mongoose.disconnect();
    process.exit(issues === 0 ? 0 : 1);
  } catch (error) {
    console.error(
      '✗ Database Health Check Error:',
      error.message
    );

    try {
      await mongoose.disconnect();
    } catch (_) {
      // Ignore disconnect errors while reporting the original failure.
    }

    process.exit(1);
  }
}

checkDatabase();