// routes/authRoutes.js  ← วางแทนทั้งไฟล์
const express = require('express');
const router = express.Router();

const multer = require('multer');
const path = require('path');
const fs = require('fs'); // ✅ ต้องมี

const {
  startRegister,
  verifyRegister,
  resendOtp,
  login,
  updateProfile,
  uploadAvatar,
} = require('../controllers/authController');

// ====== Multer upload config ======
const dest = path.join(__dirname, '..', 'uploads', 'avatars');
if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, dest),
  filename: (req, file, cb) => {
    const ext = (path.extname(file.originalname) || '.jpg').toLowerCase();
    const safe = Date.now() + '_' + Math.random().toString(36).slice(2) + ext;
    cb(null, safe);
  },
});

// ผ่อนกฎ fileFilter ให้รองรับ image/* และ fallback จากนามสกุล (กันเคส HEIC/GIF/บางรุ่นส่ง octet-stream)
const allowedExts = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.heic', '.heif']);
const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
  fileFilter: (req, file, cb) => {
    const mt = (file.mimetype || '').toLowerCase();
    const ext = (path.extname(file.originalname) || '').toLowerCase();

    console.log('[uploadAvatar] mimetype=', mt, ' name=', file.originalname);

    if (mt.startsWith('image/')) return cb(null, true);
    if (allowedExts.has(ext)) return cb(null, true);

    return cb(new Error('invalid file type'));
  },
});

// ====== Auth / OTP ======
router.post('/register/request-otp', startRegister);
router.post('/register/verify',       verifyRegister);
router.post('/register/resend-otp',   resendOtp);

// ====== Login ======
router.post('/login', login);

// ====== Profile ======
router.post('/profile/update',  updateProfile);
router.post('/profile/avatar',  upload.single('avatar'), uploadAvatar); // field ชื่อ "avatar"

module.exports = router;
