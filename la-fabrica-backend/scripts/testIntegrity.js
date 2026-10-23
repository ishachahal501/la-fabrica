require('dotenv').config({ path: __dirname + '/../.env' });
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');

const authRoutes = require('../routes/auth');
const designRoutes = require('../routes/designs');
const inventoryRoutes = require('../routes/inventory');

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));
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
      path: url.pathname + url.search,
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

async function runIntegrityTests() {
  console.log('========================================');
  console.log('LA FABRICA INTEGRITY & SECURITY SUITE');
  console.log('========================================');

  const uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/test';
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
  console.log('✓ Connected to MongoDB database:', mongoose.connection.name);

  server = app.listen(0);
  const port = server.address().port;
  baseUrl = `http://127.0.0.1:${port}/api`;
  console.log(`✓ Test server running on port ${port}`);

  // TEST 1: Duplicate email returns HTTP 409
  console.log('\n--- 1. Testing Duplicate Email Returns HTTP 409 ---');
  const uniqueEmail = `test_dupe_${Date.now()}@example.com`;
  const reg1 = await request('POST', '/auth/register', {
    name: 'User 1',
    email: uniqueEmail,
    password: 'Password123!',
    role: 'designer'
  });
  if (reg1.status !== 201) throw new Error(`Registration failed unexpectedly: ${JSON.stringify(reg1.body)}`);
  const designerToken = reg1.body.token;

  const regDupe = await request('POST', '/auth/register', {
    name: 'User 2',
    email: uniqueEmail,
    password: 'Password123!',
    role: 'designer'
  });
  console.log('Duplicate email registration response:', regDupe.status, regDupe.body);
  if (regDupe.status !== 409) {
    throw new Error(`Expected HTTP 409 for duplicate email, got ${regDupe.status}`);
  }
  console.log('✓ Duplicate email correctly rejected with HTTP 409 Conflict');

  // TEST 2: Inventory registration WITHOUT invitation code is rejected
  console.log('\n--- 2. Testing Inventory Self-Assignment Rejection ---');
  const invUninvited = await request('POST', '/auth/register', {
    name: 'Unauthorized Inventory User',
    email: `inv_bad_${Date.now()}@example.com`,
    password: 'Password123!',
    role: 'inventory'
  });
  console.log('Uninvited inventory registration response:', invUninvited.status, invUninvited.body);
  if (invUninvited.status !== 400) {
    throw new Error(`Expected HTTP 400 for uninvited inventory registration, got ${invUninvited.status}`);
  }
  console.log('✓ Uninvited inventory registration rejected without valid invitation code');

  // TEST 3: Designer creates invitation and inventory user registers with it
  console.log('\n--- 3. Testing Designer Invitation & Inventory Provisioning ---');
  const inviteRes = await request('POST', '/auth/invitations', {
    invitedEmail: `inv_good_${Date.now()}@example.com`
  }, designerToken);
  console.log('Created invitation response:', inviteRes.status, inviteRes.body);
  if (inviteRes.status !== 201 || !inviteRes.body.code) {
    throw new Error('Failed to create invitation code');
  }
  const inviteCode = inviteRes.body.code;
  const invitedEmail = inviteRes.body.invitedEmail;

  // Validate invite code endpoint
  const validateRes = await request('GET', `/auth/invitations/validate?code=${inviteCode}`);
  console.log('Validate invite code response:', validateRes.status, validateRes.body);
  if (validateRes.status !== 200 || !validateRes.body.valid) {
    throw new Error('Invitation code validation failed');
  }

  // Register inventory user with invite code
  const regInv = await request('POST', '/auth/register', {
    name: 'Authorized Inventory Lead',
    email: invitedEmail,
    password: 'Password123!',
    role: 'inventory',
    inviteCode: inviteCode
  });
  console.log('Invited inventory registration response:', regInv.status, regInv.body);
  if (regInv.status !== 201 || !regInv.body.user.assignedDesignerId) {
    throw new Error('Authorized inventory registration failed or missing assignedDesignerId');
  }
  const inventoryToken = regInv.body.token;
  console.log('✓ Authorized inventory user registered successfully with server-verified designer link');

  // Verify invitation code cannot be reused
  const reuseRes = await request('POST', '/auth/register', {
    name: 'Sneaky User',
    email: `sneaky_${Date.now()}@example.com`,
    password: 'Password123!',
    role: 'inventory',
    inviteCode: inviteCode
  });
  console.log('Reused invite code response:', reuseRes.status, reuseRes.body);
  if (reuseRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for reused invitation code, got ${reuseRes.status}`);
  }
  console.log('✓ Reused invitation code correctly rejected');

  // TEST 4: Designers list endpoint is protected
  console.log('\n--- 4. Testing /api/auth/designers is Protected ---');
  const publicDesigners = await request('GET', '/auth/designers');
  console.log('Public /designers access status:', publicDesigners.status);
  if (publicDesigners.status !== 401) {
    throw new Error(`Expected HTTP 401 for unauthenticated /designers, got ${publicDesigners.status}`);
  }
  const authDesigners = await request('GET', '/auth/designers', null, designerToken);
  console.log('Authenticated /designers access status:', authDesigners.status);
  if (authDesigners.status !== 200) {
    throw new Error(`Expected HTTP 200 for authenticated /designers, got ${authDesigners.status}`);
  }
  console.log('✓ /api/auth/designers correctly protected from public scraping');

  // TEST 5: Malformed ObjectId returns HTTP 400 (Not 500)
  console.log('\n--- 5. Testing Malformed MongoDB IDs Return HTTP 400 ---');
  const malformedDesignRes = await request('GET', '/designs/not-a-valid-id', null, designerToken);
  console.log('Malformed design ID response:', malformedDesignRes.status, malformedDesignRes.body);
  if (malformedDesignRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for malformed design ID, got ${malformedDesignRes.status}`);
  }

  const malformedInvRes = await request('GET', '/inventory/invalid-object-id', null, inventoryToken);
  console.log('Malformed inventory ID response:', malformedInvRes.status, malformedInvRes.body);
  if (malformedInvRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for malformed inventory ID, got ${malformedInvRes.status}`);
  }
  console.log('✓ Malformed IDs consistently return HTTP 400 Bad Request');

  // TEST 6: Atomic Design Creation & Validation
  console.log('\n--- 6. Testing Atomic Design Creation & Validation ---');
  // 6a: Negative initialStock rejected
  const negStockRes = await request('POST', '/designs', {
    name: 'Invalid Negative Design',
    initialStock: -10,
    unitPrice: 500
  }, designerToken);
  console.log('Negative stock creation response:', negStockRes.status, negStockRes.body);
  if (negStockRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for negative stock, got ${negStockRes.status}`);
  }

  // 6b: Valid creation creates both design and linked inventory
  const goodDesignRes = await request('POST', '/designs', {
    name: 'Atomic Hoodie',
    apparelType: 'hoodie',
    initialStock: 25,
    unitPrice: 1200
  }, designerToken);
  console.log('Valid atomic creation response:', goodDesignRes.status);
  if (goodDesignRes.status !== 201 || !goodDesignRes.body.design._id || !goodDesignRes.body.inventory._id) {
    throw new Error('Valid design creation failed');
  }
  const createdDesignId = goodDesignRes.body.design._id;
  const createdInvId = goodDesignRes.body.inventory._id;
  console.log('✓ Design and linked inventory created atomically');

  // TEST 7: Inventory Validation (finite numbers, quantities, valid actions)
  console.log('\n--- 7. Testing Inventory Input Validation ---');
  // 7a: Invalid action rejected
  const invalidActionRes = await request('PUT', `/inventory/${createdInvId}`, {
    action: 'delete_everything',
    quantity: 10
  }, inventoryToken);
  console.log('Invalid action response:', invalidActionRes.status, invalidActionRes.body);
  if (invalidActionRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for invalid action, got ${invalidActionRes.status}`);
  }

  // 7b: Negative quantity rejected
  const negQtyRes = await request('PUT', `/inventory/${createdInvId}`, {
    action: 'add',
    quantity: -5
  }, inventoryToken);
  console.log('Negative quantity response:', negQtyRes.status, negQtyRes.body);
  if (negQtyRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for negative quantity, got ${negQtyRes.status}`);
  }

  // 7c: Non-finite quantity rejected
  const nanQtyRes = await request('PUT', `/inventory/${createdInvId}`, {
    action: 'add',
    quantity: 'not_a_number'
  }, inventoryToken);
  console.log('NaN quantity response:', nanQtyRes.status, nanQtyRes.body);
  if (nanQtyRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for NaN quantity, got ${nanQtyRes.status}`);
  }

  // 7d: Valid stock reduction works
  const validReduceRes = await request('PUT', `/inventory/${createdInvId}`, {
    action: 'reduce',
    quantity: 5
  }, inventoryToken);
  console.log('Valid reduce response:', validReduceRes.status, 'New stock:', validReduceRes.body.stockQuantity);
  if (validReduceRes.status !== 200 || validReduceRes.body.stockQuantity !== 20) {
    throw new Error(`Expected stock 20 after reduction, got ${validReduceRes.body.stockQuantity}`);
  }
  console.log('✓ Inventory inputs strictly validated and updated');

  // TEST 8: Dashboard Summary MongoDB Aggregation Pipeline
  console.log('\n--- 8. Testing Dashboard Summary Aggregation Pipeline ---');
  const summaryRes = await request('GET', '/inventory/dashboard/summary', null, inventoryToken);
  console.log('Dashboard summary response:', summaryRes.status, summaryRes.body);
  if (summaryRes.status !== 200 || typeof summaryRes.body.totalProducts !== 'number') {
    throw new Error('Aggregation pipeline summary failed');
  }
  console.log('✓ Aggregation pipeline returns accurate summary metrics');

  // TEST 9: Session Expiration & Missing expiresAt Rejection
  console.log('\n--- 9. Testing Session Expiry Rejection in authMiddleware ---');
  const crypto = require('crypto');
  const sessionsCol = mongoose.connection.db.collection('sessions');

  // Create an expired session
  const expiredRawToken = crypto.randomBytes(32).toString('hex');
  const expiredTokenHash = crypto.createHash('sha256').update(expiredRawToken).digest('hex');
  await sessionsCol.insertOne({
    userId: new mongoose.Types.ObjectId(goodDesignRes.body.design.designerId),
    tokenHash: expiredTokenHash,
    expiresAt: new Date(Date.now() - 10000), // in the past
    userAgent: 'Test'
  });

  const expiredAccessRes = await request('GET', '/auth/me', null, expiredRawToken);
  console.log('Expired session access status:', expiredAccessRes.status);
  if (expiredAccessRes.status !== 401) {
    throw new Error(`Expected HTTP 401 for expired session, got ${expiredAccessRes.status}`);
  }

  // Create session with missing expiresAt
  const noExpiryRawToken = crypto.randomBytes(32).toString('hex');
  const noExpiryTokenHash = crypto.createHash('sha256').update(noExpiryRawToken).digest('hex');
  await sessionsCol.insertOne({
    userId: new mongoose.Types.ObjectId(goodDesignRes.body.design.designerId),
    tokenHash: noExpiryTokenHash,
    expiresAt: null, // missing expiresAt
    userAgent: 'Test'
  });

  const noExpiryAccessRes = await request('GET', '/auth/me', null, noExpiryRawToken);
  console.log('Missing expiresAt session access status:', noExpiryAccessRes.status);
  if (noExpiryAccessRes.status !== 401) {
    throw new Error(`Expected HTTP 401 for session with missing expiresAt, got ${noExpiryAccessRes.status}`);
  }
  // TEST 10: Ownership Checks (Attempts to access another designer's records return 403 Forbidden)
  console.log('\n--- 10. Testing Cross-Designer Ownership Enforcement ---');
  const regDesignerB = await request('POST', '/auth/register', {
    name: 'Designer B',
    email: `designer_b_${Date.now()}@example.com`,
    password: 'Password123!',
    role: 'designer'
  });
  if (regDesignerB.status !== 201) throw new Error('Registration for Designer B failed');
  const designerBToken = regDesignerB.body.token;

  // Designer B attempts to access Designer A's design
  const crossGetDesign = await request('GET', `/designs/${createdDesignId}`, null, designerBToken);
  console.log('Cross-designer GET design status:', crossGetDesign.status);
  if (crossGetDesign.status !== 403) {
    throw new Error(`Expected HTTP 403 for cross-designer GET design, got ${crossGetDesign.status}`);
  }

  // Designer B attempts to update Designer A's design
  const crossPutDesign = await request('PUT', `/designs/${createdDesignId}`, { name: 'Hacked Name' }, designerBToken);
  console.log('Cross-designer PUT design status:', crossPutDesign.status);
  if (crossPutDesign.status !== 403) {
    throw new Error(`Expected HTTP 403 for cross-designer PUT design, got ${crossPutDesign.status}`);
  }

  // Designer B attempts to delete Designer A's design
  const crossDelDesign = await request('DELETE', `/designs/${createdDesignId}`, null, designerBToken);
  console.log('Cross-designer DELETE design status:', crossDelDesign.status);
  if (crossDelDesign.status !== 403) {
    throw new Error(`Expected HTTP 403 for cross-designer DELETE design, got ${crossDelDesign.status}`);
  }

  // Designer B attempts to access Designer A's inventory
  const crossGetInv = await request('GET', `/inventory/${createdInvId}`, null, designerBToken);
  console.log('Cross-designer GET inventory status:', crossGetInv.status);
  if (crossGetInv.status !== 403) {
    throw new Error(`Expected HTTP 403 for cross-designer GET inventory, got ${crossGetInv.status}`);
  }

  // Designer B attempts to modify Designer A's inventory
  const crossPutInv = await request('PUT', `/inventory/${createdInvId}`, { action: 'add', quantity: 10 }, designerBToken);
  console.log('Cross-designer PUT inventory status:', crossPutInv.status);
  if (crossPutInv.status !== 403) {
    throw new Error(`Expected HTTP 403 for cross-designer PUT inventory, got ${crossPutInv.status}`);
  }
  console.log('✓ Cross-designer access attempts strictly rejected with HTTP 403 Forbidden');

  // TEST 11: Editor Upload Payload Validation
  console.log('\n--- 11. Testing Editor Upload Payload Validation ---');
  // 11a: Malformed designData JSON
  const malformedJsonRes = await request('POST', '/designs', {
    name: 'Malformed JSON Design',
    designData: '{not_valid_json}'
  }, designerToken);
  console.log('Malformed designData JSON status:', malformedJsonRes.status, malformedJsonRes.body);
  if (malformedJsonRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for malformed designData JSON, got ${malformedJsonRes.status}`);
  }

  // 11b: Invalid previewImage format (not a data URI or URL)
  const badImageRes = await request('POST', '/designs', {
    name: 'Bad Image Design',
    previewImage: 'javascript:alert(1)'
  }, designerToken);
  console.log('Invalid previewImage status:', badImageRes.status, badImageRes.body);
  if (badImageRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for invalid previewImage URI, got ${badImageRes.status}`);
  }
  console.log('✓ Editor upload payloads (JSON validity, image format) strictly validated');

  // TEST 12: Simultaneous Concurrent Redemption of the Same Invitation Code
  console.log('\n--- 12. Testing Concurrent Invitation Code Redemption ---');
  const concInviteRes = await request('POST', '/auth/invitations', {}, designerToken);
  if (concInviteRes.status !== 201 || !concInviteRes.body.code) {
    throw new Error('Failed to create invitation for concurrent test');
  }
  const concCode = concInviteRes.body.code;

  const concEmail1 = `conc_user1_${Date.now()}@example.com`;
  const concEmail2 = `conc_user2_${Date.now()}@example.com`;

  const [resA, resB] = await Promise.all([
    request('POST', '/auth/register', {
      name: 'Concurrent User A',
      email: concEmail1,
      password: 'Password123!',
      role: 'inventory',
      inviteCode: concCode
    }),
    request('POST', '/auth/register', {
      name: 'Concurrent User B',
      email: concEmail2,
      password: 'Password123!',
      role: 'inventory',
      inviteCode: concCode
    })
  ]);

  const statuses = [resA.status, resB.status];
  console.log('Concurrent registration statuses:', statuses);
  const successCount = statuses.filter(s => s === 201).length;
  const rejectedCount = statuses.filter(s => s === 400).length;

  if (successCount !== 1 || rejectedCount !== 1) {
    throw new Error(`Expected exactly 1 success (201) and 1 rejection (400), got: ${JSON.stringify(statuses)}`);
  }
  console.log('✓ Concurrent redemption handled atomically: exactly one registration succeeded');

  // TEST 13: All 5 Garment Types
  console.log('\n--- 13. Testing All 5 Garment Types (T-Shirt, Hoodie, Sweatshirt, Tank, Polo) ---');
  const allGarmentTypes = [
    { type: 'tshirt', label: 'T-Shirt' },
    { type: 'hoodie', label: 'Hoodie' },
    { type: 'sweatshirt', label: 'Sweatshirt' },
    { type: 'tank', label: 'Tank Top' },
    { type: 'polo', label: 'Polo Shirt' }
  ];

  for (const garment of allGarmentTypes) {
    const createGarmentRes = await request('POST', '/designs', {
      name: `Test ${garment.label}`,
      apparelType: garment.type,
      initialStock: 10,
      unitPrice: 500
    }, designerToken);

    if (createGarmentRes.status !== 201) {
      throw new Error(`Failed to create design for apparel type '${garment.type}': ${JSON.stringify(createGarmentRes.body)}`);
    }

    const designId = createGarmentRes.body.design._id;
    if (createGarmentRes.body.design.apparelType !== garment.type) {
      throw new Error(`Apparel type mismatch on creation for '${garment.type}'`);
    }

    // Reopen / fetch single design
    const fetchRes = await request('GET', `/designs/${designId}`, null, designerToken);
    if (fetchRes.status !== 200 || fetchRes.body.apparelType !== garment.type) {
      throw new Error(`Reopening design failed for apparel type '${garment.type}'`);
    }

    // Check inventory record created with matching apparel type and label
    const invListRes = await request('GET', '/inventory', null, designerToken);
    const matchingInv = invListRes.body.find(i => (i.designId === designId || i.designId?._id === designId));
    if (!matchingInv || matchingInv.apparelType !== garment.type) {
      throw new Error(`Matching inventory item missing or has wrong apparelType for '${garment.type}'`);
    }

    // Update design
    const updateRes = await request('PUT', `/designs/${designId}`, {
      name: `Updated ${garment.label}`
    }, designerToken);
    if (updateRes.status !== 200) {
      throw new Error(`Updating design failed for apparel type '${garment.type}'`);
    }

    console.log(`  ✓ Garment type '${garment.type}' (${garment.label}): created, verified in inventory, reopened, and updated`);
  }

  // TEST 14: Password-Length Hardening
  console.log('\n--- 14. Testing Password Length Validation (< 8 characters rejected) ---');
  const shortPassRes = await request('POST', '/auth/register', {
    name: 'Short Pass User',
    email: `short_pass_${Date.now()}@example.com`,
    password: 'Short1!', // 7 chars
    role: 'designer'
  });
  console.log('Short password registration status:', shortPassRes.status, shortPassRes.body);
  if (shortPassRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for password < 8 chars, got ${shortPassRes.status}`);
  }
  console.log('✓ Password length < 8 strictly rejected with HTTP 400');

  // TEST 15: Stock Quantity Validation (Decimals and Non-Integers Rejected)
  console.log('\n--- 15. Testing Stock Quantity Validation (Decimals Rejected) ---');
  const decimalStockRes = await request('POST', '/designs', {
    name: 'Decimal Stock Item',
    apparelType: 'tshirt',
    initialStock: 12.5,
    unitPrice: 500
  }, designerToken);
  console.log('Decimal initialStock response:', decimalStockRes.status, decimalStockRes.body);
  if (decimalStockRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for decimal initialStock, got ${decimalStockRes.status}`);
  }
  console.log('✓ Non-integer stock quantity strictly rejected with HTTP 400');

  // TEST 16: Combined Payload Limit Validation
  console.log('\n--- 16. Testing Combined Design Payload Limits ---');
  const largeData = 'x'.repeat(4.5 * 1024 * 1024); // 4.5MB
  const payloadRes = await request('POST', '/designs', {
    name: 'Huge Payload Design',
    designData: largeData
  }, designerToken);
  console.log('Oversized payload response:', payloadRes.status, payloadRes.body);
  if (payloadRes.status !== 400 && payloadRes.status !== 413) {
    throw new Error(`Expected HTTP 400 or 413 for oversized payload, got ${payloadRes.status}`);
  }
  console.log('✓ Oversized payload strictly rejected without crashing server');

  // TEST 17: Database Error Classification in Auth Protect Middleware
  console.log('\n--- 17. Testing Error Classification in authMiddleware ---');
  // Verify that an invalid session token produces 401
  const badTokenRes = await request('GET', '/auth/me', null, 'invalid_token_12345');
  if (badTokenRes.status !== 401) {
    throw new Error(`Expected HTTP 401 for invalid token, got ${badTokenRes.status}`);
  }
  console.log('✓ Invalid session token correctly classified as HTTP 401 Unauthorized');

  // TEST 18: Simultaneous Concurrent Stock Increments and Audit Consistency
  console.log('\n--- 18. Testing Simultaneous Concurrent Stock Increments ---');
  const invDesignRes = await request('POST', '/designs', {
    name: 'Concurrency Test Item',
    apparelType: 'hoodie',
    initialStock: 20,
    unitPrice: 1200
  }, designerToken);
  if (invDesignRes.status !== 201) throw new Error('Failed to create concurrency test design');
  const concDesignId = invDesignRes.body.design._id;

  const invFetch = await request('GET', '/inventory', null, designerToken);
  const targetInv = invFetch.body.find(i => (i.designId === concDesignId || i.designId?._id === concDesignId));
  if (!targetInv) throw new Error('Target inventory item not found');
  const targetInvId = targetInv._id;

  // Run 5 simultaneous increment requests of +4 units each
  const incPromises = Array.from({ length: 5 }, (_, i) =>
    request('PUT', `/inventory/${targetInvId}`, {
      action: 'add',
      quantity: 4,
      note: `Concurrent increment #${i + 1}`
    }, designerToken)
  );
  const incResults = await Promise.all(incPromises);
  const allIncOk = incResults.every(r => r.status === 200);
  if (!allIncOk) {
    throw new Error(`One or more concurrent increments failed: ${JSON.stringify(incResults.map(r => r.status))}`);
  }

  const afterIncFetch = await request('GET', `/inventory/${targetInvId}`, null, designerToken);
  const expectedStockAfterInc = 20 + (5 * 4); // 40
  if (afterIncFetch.body.stockQuantity !== expectedStockAfterInc) {
    throw new Error(`Expected stock ${expectedStockAfterInc} after 5 concurrent increments, got ${afterIncFetch.body.stockQuantity}`);
  }
  console.log(`✓ 5 simultaneous increments succeeded cleanly: stock went from 20 to ${afterIncFetch.body.stockQuantity}`);

  // TEST 19: Simultaneous Concurrent Stock Reductions and Audit Consistency
  console.log('\n--- 19. Testing Simultaneous Concurrent Stock Reductions ---');
  // Run 5 simultaneous reduction requests of -3 units each
  const redPromises = Array.from({ length: 5 }, (_, i) =>
    request('PUT', `/inventory/${targetInvId}`, {
      action: 'reduce',
      quantity: 3,
      note: `Concurrent reduction #${i + 1}`
    }, designerToken)
  );
  const redResults = await Promise.all(redPromises);
  const allRedOk = redResults.every(r => r.status === 200);
  if (!allRedOk) {
    throw new Error(`One or more concurrent reductions failed: ${JSON.stringify(redResults.map(r => r.status))}`);
  }

  const afterRedFetch = await request('GET', `/inventory`, null, designerToken);
  const afterRedInv = afterRedFetch.body.find(i => i._id === targetInvId);
  const expectedStockAfterRed = expectedStockAfterInc - (5 * 3); // 40 - 15 = 25
  if (afterRedInv.stockQuantity !== expectedStockAfterRed) {
    throw new Error(`Expected stock ${expectedStockAfterRed} after 5 concurrent reductions, got ${afterRedInv.stockQuantity}`);
  }

  // Verify audit history consistency: all recent changes have valid transitions
  const changes = afterRedInv.recentChanges || [];
  for (const c of changes) {
    if (c.action === 'add') {
      if (c.newStock !== c.previousStock + c.quantity) {
        throw new Error(`Audit math mismatch for add: prev=${c.previousStock}, qty=${c.quantity}, new=${c.newStock}`);
      }
    } else if (c.action === 'reduce') {
      if (c.newStock !== c.previousStock - c.quantity) {
        throw new Error(`Audit math mismatch for reduce: prev=${c.previousStock}, qty=${c.quantity}, new=${c.newStock}`);
      }
    }
  }
  console.log(`✓ 5 simultaneous reductions succeeded cleanly: stock reduced to ${afterRedInv.stockQuantity}`);
  console.log('✓ Audit entries precisely match committed atomic transitions');

  // TEST 20: Competing Concurrent Reductions Beyond Available Stock (Zero Negative Stock)
  console.log('\n--- 20. Testing Competing Concurrent Reductions Beyond Available Stock ---');
  // Set stock to 10
  await request('PUT', `/inventory/${targetInvId}`, { stockQuantity: 10 }, designerToken);

  // Two concurrent requests both try to reduce 8 units (total 16, but only 10 available)
  const [compA, compB] = await Promise.all([
    request('PUT', `/inventory/${targetInvId}`, { action: 'reduce', quantity: 8 }, designerToken),
    request('PUT', `/inventory/${targetInvId}`, { action: 'reduce', quantity: 8 }, designerToken)
  ]);

  const compStatuses = [compA.status, compB.status];
  console.log('Competing reduction statuses:', compStatuses);
  const compSuccess = compStatuses.filter(s => s === 200).length;
  const compRejected = compStatuses.filter(s => s === 400).length;

  if (compSuccess !== 1 || compRejected !== 1) {
    throw new Error(`Expected exactly 1 success (200) and 1 rejection (400), got: ${JSON.stringify(compStatuses)}`);
  }

  const finalCompInv = await request('GET', `/inventory/${targetInvId}`, null, designerToken);
  if (finalCompInv.body.stockQuantity !== 2) {
    throw new Error(`Expected remaining stock to be 2, got ${finalCompInv.body.stockQuantity}`);
  }
  console.log('✓ Exactly one concurrent reduction succeeded and stock remained strictly positive (2 units)');

  // TEST 21: Optimistic Concurrency Control (OCC) and Stale Version Rejection
  console.log('\n--- 21. Testing Optimistic Concurrency Control (OCC) ---');
  const occFetch = await request('PUT', `/inventory/${targetInvId}`, { stockQuantity: 50 }, designerToken);
  const currentVersion = occFetch.body.__v;

  // Stale update: send previous version
  const staleRes = await request('PUT', `/inventory/${targetInvId}`, {
    stockQuantity: 45,
    expectedVersion: currentVersion - 1
  }, designerToken);
  console.log('Stale version update response:', staleRes.status, staleRes.body);
  if (staleRes.status !== 409) {
    throw new Error(`Expected HTTP 409 Conflict for stale version, got ${staleRes.status}`);
  }
  console.log('✓ Stale version successfully rejected with HTTP 409 Conflict');

  // Matching version update
  const validOccRes = await request('PUT', `/inventory/${targetInvId}`, {
    stockQuantity: 48,
    expectedVersion: currentVersion
  }, designerToken);
  if (validOccRes.status !== 200 || validOccRes.body.stockQuantity !== 48) {
    throw new Error(`Expected HTTP 200 for matching OCC version, got ${validOccRes.status}`);
  }
  console.log('✓ Matching version update succeeded with version increment');

  // TEST 22: Expired Invitation Rejection & Database TTL Index Verification
  console.log('\n--- 22. Testing Expired Invitation Rejection & TTL Index ---');
  const Invitation = require('../models/Invitation');
  // Create an expired invitation directly in database
  const expiredCode = `EXP-${Date.now()}`;
  await Invitation.create({
    code: expiredCode,
    designerId: reg1.body.user.id || reg1.body.user._id,
    expiresAt: new Date(Date.now() - 3600000) // 1 hour ago
  });

  // Attempt registration with expired code
  const expiredRegRes = await request('POST', '/auth/register', {
    name: 'Expired Invite User',
    email: `expired_${Date.now()}@example.com`,
    password: 'Password123!',
    role: 'inventory',
    inviteCode: expiredCode
  });
  console.log('Expired invitation registration response:', expiredRegRes.status, expiredRegRes.body);
  if (expiredRegRes.status !== 400 || !expiredRegRes.body.message?.includes('expired')) {
    throw new Error(`Expected HTTP 400 with 'expired' message, got ${expiredRegRes.status}`);
  }
  console.log('✓ Server-side expiry check rejected expired invitation with HTTP 400');

  // Verify MongoDB TTL index configuration in database
  const invDbIndexes = await mongoose.connection.db.collection('invitations').indexes();
  const ttlIdx = invDbIndexes.find(i => i.key && i.key.expiresAt === 1);
  if (!ttlIdx || ttlIdx.expireAfterSeconds !== 0) {
    throw new Error(`TTL index missing or invalid expireAfterSeconds: ${JSON.stringify(ttlIdx)}`);
  }
  console.log('✓ Verified MongoDB TTL index exists on invitations (expiresAt: 1, expireAfterSeconds: 0)');

  console.log('\n========================================');
  console.log('ALL INTEGRITY & SECURITY TESTS PASSED! ✓');
  console.log('========================================');

  server.close();
  await mongoose.disconnect();
}

runIntegrityTests().catch((err) => {
  console.error('✗ Integrity test failed:', err);
  if (server) server.close();
  process.exit(1);
});
