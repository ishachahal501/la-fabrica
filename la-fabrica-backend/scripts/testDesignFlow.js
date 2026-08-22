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

async function runDesignTests() {
  console.log('====================================');
  console.log('LA FABRICA DESIGN & INVENTORY FLOW TEST');
  console.log('====================================');

  let uri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/test';
  const localUri = 'mongodb://127.0.0.1:27017/test';
  try {
    await mongoose.connect(uri, { serverSelectionTimeoutMS: 4000 });
  } catch (_) {
    await mongoose.connect(localUri, { serverSelectionTimeoutMS: 4000 });
  }

  server = app.listen(0);
  const port = server.address().port;
  baseUrl = `http://127.0.0.1:${port}/api`;

  const designsCol = mongoose.connection.db.collection('designs');
  const inventoriesCol = mongoose.connection.db.collection('inventories');

  // 1. Register Designer
  const designerRes = await request('POST', '/auth/register', {
    name: 'Fashion Lead',
    email: `lead_${Date.now()}@example.com`,
    password: 'Password123!',
    role: 'designer'
  });
  const token = designerRes.body.token;
  const designerId = designerRes.body.user.id;

  // 2. Create Design
  console.log('\n1. Create Design...');
  const designRes = await request('POST', '/designs', {
    name: 'Midnight Hoodie',
    apparelType: 'hoodie',
    initialStock: 40,
    unitPrice: 850
  }, token);

  console.log('Create Design Status:', designRes.status);
  const designId = designRes.body.design._id;
  console.log('Created Design ID:', designId);

  // Verify MongoDB document counts
  const designDoc = await designsCol.findOne({ _id: new mongoose.Types.ObjectId(designId) });
  const invDocs = await inventoriesCol.find({ designId: new mongoose.Types.ObjectId(designId) }).toArray();

  console.log('✓ Design document in MongoDB designs:', designDoc ? designDoc.name : null);
  console.log('✓ Linked inventory documents in MongoDB inventories:', invDocs.length);
  if (invDocs.length !== 1) throw new Error('Expected exactly 1 linked inventory document!');

  // 3. Edit Design (PUT /api/designs/:id)
  console.log('\n2. Edit Design (Save DesignData)...');
  const editRes = await request('PUT', `/designs/${designId}`, {
    designData: JSON.stringify({ apparelType: 'hoodie', apparelColor: '#1A1A1A', elements: [{ id: '1', type: 'text', content: 'MIDNIGHT' }] })
  }, token);

  console.log('Edit Design Status:', editRes.status);
  const updatedDesign = await designsCol.findOne({ _id: new mongoose.Types.ObjectId(designId) });
  const invDocsAfterEdit = await inventoriesCol.find({ designId: new mongoose.Types.ObjectId(designId) }).toArray();

  console.log('✓ designData updated in MongoDB:', updatedDesign.designData.includes('MIDNIGHT'));
  console.log('✓ Inventory documents count after design save:', invDocsAfterEdit.length);
  if (invDocsAfterEdit.length !== 1) throw new Error('Design save created duplicate inventory document!');

  console.log('\n====================================');
  console.log('DESIGN & INVENTORY FLOW TEST: PASS');
  console.log('====================================');

  server.close();
  await mongoose.disconnect();
}

runDesignTests().catch((err) => {
  console.error('✗ Test failed:', err);
  if (server) server.close();
  process.exit(1);
});
