require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const pool = require('./models/db');
const authRoutes = require('./routes/authRoutes');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Routes
app.use('/api/auth', authRoutes);

// DB test
pool.query('SELECT NOW()', (err, r) => {
  if (err) console.error('❌ DB failed:', err);
  else console.log('✅ PostgreSQL at:', r.rows[0].now);
});

// Start server
app.listen(PORT, () => console.log(`🚀 http://localhost:${PORT}`));
