const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const post = require('../controllers/postController');

// ---------- เตรียมโฟลเดอร์อัปโหลดสำหรับโพสต์ ----------
const ensureDir = (p) => { if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true }); };
const postImagesDir = path.join(__dirname, '..', 'uploads', 'post_images');
const postFilesDir  = path.join(__dirname, '..', 'uploads', 'post_files');
[postImagesDir, postFilesDir].forEach(ensureDir);

// ---------- Multer: โพสต์ (รูป/ไฟล์) ----------
const postStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    if (file.fieldname === 'image') return cb(null, postImagesDir);
    return cb(null, postFilesDir);
  },
  filename: (req, file, cb) => {
    const fallback = file.fieldname === 'image' ? '.jpg' : '.bin';
    const ext = (path.extname(file.originalname) || fallback).toLowerCase();
    const safe = Date.now() + '_' + Math.random().toString(36).slice(2) + ext;
    cb(null, safe);
  },
});

const uploadPost = multer({
  storage: postStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB ต่อไฟล์
});

// ---------- Routes: โพสต์ & ฟีด ----------
router.get('/subject/:subject', post.getPostsBySubject);
router.get('/feed', post.getFeed);

// สร้างโพสต์ (รองรับหลายรูป: field name = "image", สูงสุด 10; ไฟล์แนบ: field name = "file", สูงสุด 1)
router.post(
  '/posts',
  uploadPost.fields([
    { name: 'image', maxCount: 10 },    // ✅ หลายรูป
    { name: 'file',  maxCount: 1  },
  ]),
  post.createPost
);

// ---------- Like / Count / Comment ----------
router.post('/posts/:id/like',      post.toggleLike);
router.get ('/posts/:id/counts',    post.getPostCounts);
router.get ('/posts/:id/comments',  post.getComments);
router.post('/posts/:id/comments',  post.addComment);

// ---------- Save / Unsave / Status / รายการที่บันทึก ----------
router.post('/posts/:id/save',        post.toggleSave);
router.get ('/posts/:id/save/status', post.getSavedStatus);
router.get ('/saved',                 post.getSavedPosts);

module.exports = router;
