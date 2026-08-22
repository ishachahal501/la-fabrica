require('dotenv').config({ path: __dirname + '/../.env' });
const mongoose = require('mongoose');

async function migrateDatabase() {
  let uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/test';
  const localUri = 'mongodb://127.0.0.1:27017/test';

  console.log('Connecting to database for migration:', uri);

  try {
    try {
      await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
    } catch (e) {
      if (uri !== localUri) {
        console.log('Atlas connection warning/timeout. Trying local MongoDB instance...');
        uri = localUri;
        await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
      } else {
        throw e;
      }
    }

    const db = mongoose.connection.db;
    console.log(`✓ Connected to database: ${mongoose.connection.name}`);

    // 1. Migrate users collection: rename password to passwordHash if needed
    const usersCol = db.collection('users');
    const usersWithOldPassword = await usersCol.find({ password: { $exists: true } }).toArray();

    if (usersWithOldPassword.length > 0) {
      console.log(`Migrating ${usersWithOldPassword.length} user documents from password to passwordHash...`);
      for (const u of usersWithOldPassword) {
        if (!u.passwordHash && u.password) {
          await usersCol.updateOne(
            { _id: u._id },
            {
              $set: { passwordHash: u.password },
              $unset: { password: "" }
            }
          );
        }
      }
      console.log('✓ Users migration complete.');
    } else {
      console.log('✓ All users already use passwordHash.');
    }

    // 2. Ensure sessions collection exists
    const collections = await db.listCollections().toArray();
    const collectionNames = collections.map(c => c.name);

    if (!collectionNames.includes('sessions')) {
      console.log('Creating sessions collection...');
      await db.createCollection('sessions');
      console.log('✓ Sessions collection created.');
    } else {
      console.log('✓ Sessions collection exists.');
    }

    await mongoose.disconnect();
    console.log('✓ Migration successfully completed.');
  } catch (err) {
    console.error('✗ Migration error:', err.message);
    process.exit(1);
  }
}

migrateDatabase();
