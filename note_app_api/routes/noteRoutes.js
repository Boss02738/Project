// routes/noteRoutes.js
const express = require('express');
const router = express.Router();

// ตัวอย่าง route ทดสอบ
router.get('/', (req, res) => {
  res.json({ message: 'Note API working' });
});

module.exports = router;
