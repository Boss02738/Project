const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');

// ตัวอย่าง route
router.post('/register', authController.register);
router.post('/login', authController.login);

router.get('/all', authController.getAllUsers);

module.exports = router;
