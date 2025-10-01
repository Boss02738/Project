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
  getUserBrief
} = require('../controllers/authController');

const { createPost, getFeed } = require('../controllers/postController');
// ================== เตรียมโฟลเดอร์อัปโหลด ==================
const ensureDir = (p) => { if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true }); };

const avatarsDir    = path.join(__dirname, '..', 'uploads', 'avatars');
const postImagesDir = path.join(__dirname, '..', 'uploads', 'post_images');
const postFilesDir  = path.join(__dirname, '..', 'uploads', 'post_files');

[avatarsDir, postImagesDir, postFilesDir].forEach(ensureDir);

// ================== Multer: อวาตาร์ ==================
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
limits: { fileSize: 20 * 1024 * 1024 }, // 5MB
  fileFilter: (req, file, cb) => {
    const mt = (file.mimetype || '').toLowerCase();
    const ext = (path.extname(file.originalname) || '').toLowerCase();
    console.log('[uploadAvatar] mimetype=', mt, ' name=', file.originalname);
    if (mt.startsWith('image/')) return cb(null, true);
    if (allowedExts.has(ext)) return cb(null, true);
    return cb(new Error('invalid file type'));
  },
});

// ================== Multer: โพสต์ (รูป/ไฟล์) ==================
const postStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    // fieldname 'image' ส่งไปที่ post_images, 'file' ส่งไปที่ post_files
    if (file.fieldname === 'image') return cb(null, postImagesDir);
    return cb(null, postFilesDir);
  },
  filename: (req, file, cb) => {
    const ext = (path.extname(file.originalname) || (file.fieldname === 'image' ? '.jpg' : '.bin')).toLowerCase();
    const safe = Date.now() + '_' + Math.random().toString(36).slice(2) + ext;
    cb(null, safe);
  },
});

const uploadPost = multer({
  storage: postStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
});

// ================== Auth / OTP ==================
router.post('/register/request-otp', startRegister);
router.post('/register/verify',       verifyRegister);
router.post('/register/resend-otp',   resendOtp);

// ================== Login ==================
router.post('/login', login);

// ================== Profile ==================
router.post('/profile/update',  updateProfile);
router.post('/profile/avatar',  uploadAvatarMulter.single('avatar'), uploadAvatar); // field ชื่อ "avatar"

// ================== ดึงข้อมูลผู้ใช้สั้นๆ ==================
router.get('/user/:id', getUserBrief);

// ================== โพสต์ & ฟีด ==================
// multipart/form-data: fields = user_id, text, year_label, subject (+ files 'image', 'file')
router.post(
  '/posts',
  uploadPost.fields([
    { name: 'image', maxCount: 1 },
    { name: 'file',  maxCount: 1 },
  ]),
  createPost
);

router.get('/posts', getFeed);

module.exports = router;
