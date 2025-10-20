// routes/authRoutes.js
const express = require('express');
const router = express.Router();

const multer = require('multer');
const path = require('path');
const fs = require('fs');

const {
  startRegister,
  verifyRegister,
  resendOtp,
  login,
  updateProfile,
  uploadAvatar,
  getUserBrief,
} = require('../controllers/authController');

// ---------- เตรียมโฟลเดอร์อัปโหลดเฉพาะอวาตาร์ ----------
const ensureDir = (p) => { if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true }); };
const avatarsDir = path.join(__dirname, '..', 'uploads', 'avatars');
ensureDir(avatarsDir);

// ---------- Multer: Avatar ----------
const avatarStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, avatarsDir),
  filename: (req, file, cb) => {
    const ext = (path.extname(file.originalname) || '.jpg').toLowerCase();
    const safe = Date.now() + '_' + Math.random().toString(36).slice(2) + ext;
    cb(null, safe);
  },
});

const allowedExts = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.heic', '.heif']);
const uploadAvatarMulter = multer({
  storage: avatarStorage,
  limits: { fileSize: 20 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const mt = (file.mimetype || '').toLowerCase();
    const ext = (path.extname(file.originalname) || '').toLowerCase();
    if (mt.startsWith('image/') || allowedExts.has(ext)) return cb(null, true);
    return cb(new Error('invalid file type'));
  },
});

// ---------- Auth / OTP ----------
router.post('/register/request-otp', startRegister);
router.post('/register/verify',       verifyRegister);
router.post('/register/resend-otp',   resendOtp);

// ---------- Login ----------
router.post('/login', login);

// ---------- Profile ----------
router.post('/profile/update',  updateProfile);
router.post('/profile/avatar',  uploadAvatarMulter.single('avatar'), uploadAvatar);

// ---------- ข้อมูลผู้ใช้แบบย่อ ----------
router.get('/user/:id', getUserBrief);

module.exports = router;
