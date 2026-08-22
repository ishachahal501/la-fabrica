require('dotenv').config({ path: __dirname + '/../.env' });
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');

const authRoutes = require('../routes/auth');
const designRoutes = require('../routes/designs');
const inventoryRoutes = require('../routes/inventory');

const app = express();
app.use(cors());
app.use(express.json());
app.use('/api/auth', authRoutes);
app.use('/api/designs', designRoutes);
app.use('/api/inventory', inventoryRoutes);

let server;
let baseUrl;

function request(method, path, body = null, token = null) {
  const http = require('http');
  return new Promise((resolve, reject) => {
    const url = new URL(baseUrl + path);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: method,
      headers: {
        'Content-Type': 'application/json',
      }
    };
    if (token) {
      options.headers['Authorization'] = `Bearer ${token}`;
    }

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve({ status: res.statusCode, body: parsed });
        } catch (_) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });

    req.on('error', (e) => reject(e));
    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runAuthTests() {
  console.log('====================================');
  console.log('LA FABRICA AUTHENTICATION FLOW TEST');
  console.log('====================================');

  // 1. Connect DB with fallback
  let uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/test';
  const localUri = 'mongodb://127.0.0.1:27017/test';
  try {
    await mongoose.connect(uri, { serverSelectionTimeoutMS: 4000 });
  } catch (_) {
    await mongoose.connect(localUri, { serverSelectionTimeoutMS: 4000 });
  }
  console.log('✓ Connected to MongoDB database:', mongoose.connection.name);

  // Start test server on random port
  server = app.listen(0);
  const port = server.address().port;
  baseUrl = `http://127.0.0.1:${port}/api`;
  console.log(`✓ In-process test server running on port ${port}`);

  const sessionsCol = mongoose.connection.db.collection('sessions');
  const usersCol = mongoose.connection.db.collection('users');

  const testEmail = `designer_${Date.now()}@example.com`;
  const testPassword = 'Password123!';

  // STEP 1: REGISTER DESIGNER
  console.log('\n1. Register Designer...');
  const regRes = await request('POST', '/auth/register', {
    name: 'Test Designer',
    email: testEmail,
    password: testPassword,
    role: 'designer'
  });
  console.log('Register Status:', regRes.status);
  console.log('Register Body:', regRes.body);

  if (regRes.status !== 201 || !regRes.body.token) {
    throw new Error('Registration failed!');
  }
  const sessionToken1 = regRes.body.token;

  // Verify MongoDB users & sessions count
  const userDoc = await usersCol.findOne({ email: testEmail });
  console.log('✓ User created in MongoDB users:', userDoc ? userDoc._id : null);
  const sessionCount1 = await sessionsCol.countDocuments({ userId: userDoc._id });
  console.log('✓ Sessions document created in MongoDB sessions. Active count:', sessionCount1);
  if (sessionCount1 !== 1) throw new Error('Expected 1 session document in MongoDB!');

  // STEP 2: GET /api/auth/me
  console.log('\n2. GET /api/auth/me with session token...');
  const meRes1 = await request('GET', '/auth/me', null, sessionToken1);
  console.log('/me Status:', meRes1.status);
  console.log('/me Body:', meRes1.body);
  if (meRes1.status !== 200 || meRes1.body.email !== testEmail) {
    throw new Error('GET /auth/me failed!');
  }
  console.log('✓ GET /auth/me verified against MongoDB session');

  // STEP 3: LOGIN AGAIN (New Session)
  console.log('\n3. Login again...');
  const loginRes = await request('POST', '/auth/login', {
    email: testEmail,
    password: testPassword
  });
  console.log('Login Status:', loginRes.status);
  const sessionToken2 = loginRes.body.token;
  const sessionCount2 = await sessionsCol.countDocuments({ userId: userDoc._id });
  console.log('✓ New session document created in MongoDB. Total active user sessions:', sessionCount2);
  if (sessionCount2 !== 2) throw new Error('Expected 2 session documents in MongoDB!');

  // STEP 4: LOGOUT (Delete Session)
  console.log('\n4. Logout second session...');
  const logoutRes = await request('POST', '/auth/logout', null, sessionToken2);
  console.log('Logout Status:', logoutRes.status);
  const sessionCount3 = await sessionsCol.countDocuments({ userId: userDoc._id });
  console.log('✓ Session document deleted from MongoDB. Remaining sessions:', sessionCount3);
  if (sessionCount3 !== 1) throw new Error('Expected 1 session document remaining in MongoDB!');

  // STEP 5: VERIFY DELETED SESSION FAILS /auth/me WITH 401
  console.log('\n5. Try GET /auth/me with logged-out session token...');
  const meResExpired = await request('GET', '/auth/me', null, sessionToken2);
  console.log('Logged-out /me Status:', meResExpired.status);
  if (meResExpired.status !== 401) {
    throw new Error('Logged-out session was not rejected!');
  }
  console.log('✓ Logged-out session correctly returns 401 Unauthorized');

  // STEP 6: MANUALLY DELETE REMAINING SESSION FROM MONGODB AND VERIFY 401
  console.log('\n6. Manually delete session from MongoDB collection...');
  await sessionsCol.deleteMany({ userId: userDoc._id });
  const meResManual = await request('GET', '/auth/me', null, sessionToken1);
  console.log('Manual deletion /me Status:', meResManual.status);
  if (meResManual.status !== 401) {
    throw new Error('Manually deleted session was not rejected!');
  }
  console.log('✓ Manually deleted MongoDB session returns 401 Unauthorized (MongoDB is authoritative!)');

  console.log('\n====================================');
  console.log('AUTHENTICATION FLOW TEST: PASS');
  console.log('====================================');

  server.close();
  await mongoose.disconnect();
}

runAuthTests().catch((err) => {
  console.error('✗ Test failed:', err);
  if (server) server.close();
  process.exit(1);
});
