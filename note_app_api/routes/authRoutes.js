const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');

const {
  startRegister, verifyRegister, resendOtp, login, updateProfile, 
} = require('../controllers/authController');

// ตั้งค่า multer เก็บไฟล์ใน uploads/avatars
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, path.join(__dirname, '..', 'uploads', 'avatars')),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    const safe = Date.now() + '_' + Math.random().toString(36).slice(2) + ext;
    cb(null, safe);
  }
});
const upload = multer({
  storage,
  limits: { fileSize: 3 * 1024 * 1024 }, // 3MB
  fileFilter: (req, file, cb) => {
    const ok = /image\/(png|jpe?g|webp)/.test(file.mimetype);
    cb(ok ? null : new Error('invalid file type'), ok);
  }
});

router.post('/register/request-otp', startRegister);
router.post('/register/verify',       verifyRegister);
router.post('/register/resend-otp',   resendOtp);
router.post('/login', login);

router.post('/profile/update',        updateProfile);

// 🔹 อัปโหลด avatar (multipart/form-data; field: avatar, email)
router.post('/profile/avatar', upload.single('avatar'), updateProfile);


module.exports = router;
