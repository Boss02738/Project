// routes/postRoutes.js
const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const post = require('../controllers/postController');

// ---------- เตรียมโฟลเดอร์อัปโหลด ----------
const ensureDir = (p) => { if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true }); };
const postImagesDir = path.join(__dirname, '..', 'uploads', 'post_images');
const postFilesDir  = path.join(__dirname, '..', 'uploads', 'post_files');
[postImagesDir, postFilesDir].forEach(ensureDir);

// ---------- Multer ----------
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    if (file.fieldname === 'images') return cb(null, postImagesDir);
    if (file.fieldname === 'file')   return cb(null, postFilesDir);
    return cb(null, postImagesDir); // fallback
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    cb(null, `${Date.now()}_${Math.random().toString(36).slice(2)}${ext}`);
  },
});

// ✅ สำคัญ: จำกัดเฉพาะ images ให้เป็น image/* ส่วน file ให้ผ่านได้
const imageExts = new Set([
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif'
]);

const fileFilter = (req, file, cb) => {
  // ไฟล์แนบทั่วไป (pdf/doc/zip) ให้ผ่าน
  if (file.fieldname === 'file') return cb(null, true);

  // รูปภาพในฟิลด์ "images" ต้องเป็น image/*
  if (file.fieldname === 'images') {
    const mimeOk = (file.mimetype && file.mimetype.startsWith('image/'));
    const extOk  = imageExts.has((require('path').extname(file.originalname || '')).toLowerCase());

    if (mimeOk || extOk) return cb(null, true);
    return cb(new Error('Only image files are allowed!'));
  }

  // ฟิลด์อื่น (ถ้ามี) ปล่อยผ่าน
  return cb(null, true);
};

const upload = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB/ไฟล์
    files: 11,                  // images(<=10) + file(<=1)
  },
});

// ---------- Routes ----------
router.post(
  '/',
  upload.fields([
    { name: 'images', maxCount: 10 }, // รูปหลายรูป
    { name: 'file',   maxCount: 1  }, // ไฟล์แนบ
  ]),
  post.createPost
);

router.get('/feed', post.getFeed);
router.get('/by-subject', post.getPostsBySubject);

// Like / Count / Comment
router.post('/posts/:id/like',      post.toggleLike);
router.get ('/posts/:id/counts',    post.getPostCounts);
router.get ('/posts/:id/comments',  post.getComments);
router.post('/posts/:id/comments',  post.addComment);

// Save
router.post('/posts/:id/save',        post.toggleSave);
router.get ('/posts/:id/save/status', post.getSavedStatus);
router.get ('/saved',                 post.getSavedPosts);
//Profile 
router.get('/user/:id', post.getPostsByUser);
module.exports = router;
