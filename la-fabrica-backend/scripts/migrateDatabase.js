require('dotenv').config({ path: __dirname + '/../.env' });
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

// Redact credentials from MongoDB connection URI
function redactUri(uri) {
  try {
    return uri.replace(/mongodb(\+srv)?:\/\/([^:]+):([^@]+)@/, 'mongodb$1://$2:****@');
  } catch (_) {
    return '[REDACTED]';
  }
}

async function migrateDatabase() {
  const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/test';

  console.log('Connecting to database for migration...');
  console.log(`Target: ${redactUri(uri)}`);

  try {
    await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
    const db = mongoose.connection.db;
    console.log(`✓ Connected to database: ${mongoose.connection.name}`);

    // 1. Migrate users collection: rename password to passwordHash if needed
    const usersCol = db.collection('users');
    const usersWithOldPassword = await usersCol.find({ password: { $exists: true } }).toArray();

    if (usersWithOldPassword.length > 0) {
      console.log(`Migrating ${usersWithOldPassword.length} user documents from password to passwordHash...`);
      for (const u of usersWithOldPassword) {
        if (!u.passwordHash && u.password) {
          let hashToSet = u.password;
          const isBcrypt = typeof u.password === 'string' && 
            (u.password.startsWith('$2a$') || u.password.startsWith('$2b$'));

          if (!isBcrypt) {
            console.log(`  -> Detected legacy plaintext password for user [${u.email}]. Hashing securely with bcrypt...`);
            const salt = await bcrypt.genSalt(10);
            hashToSet = await bcrypt.hash(u.password, salt);
          }

          await usersCol.updateOne(
            { _id: u._id },
            {
              $set: { passwordHash: hashToSet },
              $unset: { password: "" }
            }
          );
        }
      }
      console.log('✓ Users migration complete.');
    } else {
      console.log('✓ All users already use passwordHash.');
    }

    // 2. Ensure sessions and invitations collections exist
    const collections = await db.listCollections().toArray();
    const collectionNames = collections.map(c => c.name);

    if (!collectionNames.includes('sessions')) {
      console.log('Creating sessions collection...');
      await db.createCollection('sessions');
      console.log('✓ Sessions collection created.');
    } else {
      console.log('✓ Sessions collection exists.');
    }

    if (!collectionNames.includes('invitations')) {
      console.log('Creating invitations collection...');
      await db.createCollection('invitations');
      console.log('✓ Invitations collection created.');
    } else {
      console.log('✓ Invitations collection exists.');
    }

    // 3. Clean up orphan inventory records referencing deleted/non-existent users
    const inventoriesCol = db.collection('inventories');
    const allUsers = await usersCol.find({}, { projection: { _id: 1 } }).toArray();
    const userIds = new Set(allUsers.map(u => u._id.toString()));
    const allInventories = await inventoriesCol.find({}).toArray();
    const orphanInvs = allInventories.filter(inv => {
      const dId = (inv.designerId || inv.user)?.toString();
      return !dId || !userIds.has(dId);
    });
    if (orphanInvs.length > 0) {
      console.log(`Cleaning up ${orphanInvs.length} orphan inventory records...`);
      for (const orphan of orphanInvs) {
        await inventoriesCol.deleteOne({ _id: orphan._id });
      }
      console.log('✓ Cleaned up orphan inventory records.');
    }

    await mongoose.disconnect();
    console.log('✓ Migration successfully completed.');
  } catch (err) {
    console.error('✗ Migration error:', err.message);
    process.exit(1);
  }
}

migrateDatabase();
