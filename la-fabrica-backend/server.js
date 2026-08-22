require('dotenv').config();

const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');

const authRoutes = require('./routes/auth');
const designRoutes = require('./routes/designs');
const inventoryRoutes = require('./routes/inventory');

const app = express();

app.use(cors());
app.use(express.json());

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/designs', designRoutes);
app.use('/api/inventory', inventoryRoutes);

// DB Connection
const dbUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/test';
const localDbUri = 'mongodb://127.0.0.1:27017/test';

async function connectDB() {
  try {
    console.log('Attempting MongoDB connection...');
    await mongoose.connect(dbUri, { serverSelectionTimeoutMS: 5000 });
    console.log('MongoDB connected successfully');
    console.log(`Database: ${mongoose.connection.name}`);
  } catch (err) {
    console.warn('Configured MongoDB Connection Error:', err.message);
    if (dbUri !== localDbUri) {
      console.log('Falling back to local MongoDB instance...');
      try {
        await mongoose.connect(localDbUri, { serverSelectionTimeoutMS: 5000 });
        console.log('MongoDB connected successfully');
        console.log(`Database: ${mongoose.connection.name}`);
      } catch (localErr) {
        console.error('Local MongoDB Connection Error:', localErr.message);
      }
    }
  }
}

connectDB();

const PORT = process.env.PORT || 5000;

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});