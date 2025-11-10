const express = require('express');
const router = express.Router();

router.get('/', (req, res) => {
  res.json({ message: 'Note API working' });
});

module.exports = router;
