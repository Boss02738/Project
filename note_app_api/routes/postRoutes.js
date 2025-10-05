// routes/postRoutes.js
const express = require('express');
const router = express.Router();
const { getPostsBySubject } = require('../controllers/postController');

router.get('/subject/:subject', getPostsBySubject); // ✅

module.exports = router;
