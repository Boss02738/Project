const express = require('express');
const router = express.Router();
const { searchUsers, searchSubjects } = require('../controllers/searchController');
router.get('/users', searchUsers);
router.get('/subjects', searchSubjects);

module.exports = router;
