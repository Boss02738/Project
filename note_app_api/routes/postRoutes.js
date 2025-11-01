// routes/postRoutes.js
const express = require('express');
const multer = require('multer');
const path = require('path');
const ctrl = require('../controllers/postController');

const router = express.Router();

/* ---- multer สำหรับสร้างโพสต์ (images multiple + file single) ---- */
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const isImage = file.fieldname === 'images';
    cb(null, path.join(process.cwd(), isImage ? 'uploads/post_images' : 'uploads/post_files'));
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    const base = path.basename(file.originalname, ext);
    cb(null, `${base}-${Date.now()}${ext}`);
  },
});
const upload = multer({ storage });

/* ---------- ROUTES (ห้ามใส่วงเล็บเรียก ctrl.fn()) ---------- */
// Create post
router.post(
  '/',
  upload.fields([
    { name: 'images', maxCount: 10 },
    { name: 'file',   maxCount: 1  },
  ]),
  ctrl.createPost
);

// Feed
router.get('/feed', ctrl.getFeed);

router.get('/purchased', ctrl.getPurchasedFeed);

// By subject
router.get('/by-subject', ctrl.getPostsBySubject);

// Like / Unlike
router.post('/posts/:id/like', ctrl.toggleLike);

// Comments
router.get('/posts/:id/comments', ctrl.getComments);
router.post('/posts/:id/comments', ctrl.addComment);

// Counts
router.get('/posts/:id/counts', ctrl.getPostCounts);

// Save / Unsave + status
router.post('/posts/:id/save', ctrl.toggleSave);
router.get('/posts/:id/save/status', ctrl.getSavedStatus);

// Saved list
router.get('/saved', ctrl.getSavedPosts);

router.get('/archived', ctrl.getArchivedPosts);

// Posts by user
router.get('/user/:id', ctrl.getPostsByUser);

// Detail
router.get('/:id', ctrl.getPostDetail);

// Archive / Unarchive / Hard delete
router.post('/:id/archive', ctrl.archivePost);
router.post('/:id/unarchive', ctrl.unarchivePost);
router.delete('/:id', ctrl.hardDeletePost);

router.get('/:id/file/download', ctrl.downloadFileProtected);      // NEW
router.get('/:id/images', ctrl.getImagesRespectAccess);   


module.exports = router;
