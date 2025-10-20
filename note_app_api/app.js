require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const pool = require('./models/db');
const path = require('path');
const fs = require('fs');

const authRoutes = require('./routes/authRoutes');
const searchRoutes = require('./routes/searchRoutes');
const postRoutes = require('./routes/postRoutes');
const app = express();
const PORT = process.env.PORT || 3000;

const uploadRoot = path.join(__dirname, 'uploads');
const avatarDir = path.join(uploadRoot, 'avatars');
if (!fs.existsSync(uploadRoot)) fs.mkdirSync(uploadRoot);
if (!fs.existsSync(avatarDir)) fs.mkdirSync(avatarDir, { recursive: true });

app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.json());                // ✅ ต้องมีสำหรับ body JSON (like/comment)

// Routes 
// auth upload 
app.use('/api/auth', authRoutes);
app.use('/api/auth', postRoutes);

app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
// search
app.use('/api/search', searchRoutes);
app.use('/api/posts', postRoutes); // ✅ path ต้องตรงกับที่ฝั่ง Flutter เรียก
// DB test
pool.query('SELECT NOW()', (err, r) => {
  if (err) console.error('❌ DB failed:', err);
  else console.log('✅ PostgreSQL at:', r.rows[0].now);
});

// Start server
app.listen(PORT, () => console.log(`🚀 http://localhost:${PORT}`));
