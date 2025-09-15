// routes/authRoutes.js
const express = require('express');
const router = express.Router();

const {
  startRegister,
  verifyRegister,
  resendOtp,
  login,
} = require('../controllers/authController');

router.post('/register/request-otp', startRegister);
router.post('/register/verify', verifyRegister);
router.post('/register/resend-otp', resendOtp);
router.post('/login', login);   

module.exports = router;
