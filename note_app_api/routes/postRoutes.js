// routes/postRoutes.js
const express = require('express');
const multer = require('multer');
const path = require('path');
const ctrl = require('../controllers/postController');

const router = express.Router();

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

router.post(
  '/',
  upload.fields([
    { name: 'images', maxCount: 10 },
    { name: 'file',   maxCount: 1  },
  ]),
  ctrl.createPost
);
router.get('/feed', ctrl.getFeed);
router.get('/purchased', ctrl.getPurchasedFeed);
router.get('/by-subject', ctrl.getPostsBySubject);
router.post('/posts/:id/like', ctrl.toggleLike);
router.get('/posts/:id/comments', ctrl.getComments);
router.post('/posts/:id/comments', ctrl.addComment);
router.get('/posts/:id/counts', ctrl.getPostCounts);
router.post('/posts/:id/save', ctrl.toggleSave);
router.get('/posts/:id/save/status', ctrl.getSavedStatus);
router.get('/saved', ctrl.getSavedPosts);
router.get('/archived', ctrl.getArchivedPosts);
router.get('/user/:id', ctrl.getPostsByUser);
router.get('/:id', ctrl.getPostDetail);
router.post('/:id/archive', ctrl.archivePost);
router.post('/:id/unarchive', ctrl.unarchivePost);
router.delete('/:id', ctrl.hardDeletePost);
router.get('/:id/file/download', ctrl.downloadFileProtected);
router.get('/:id/images', ctrl.getImagesRespectAccess);   


module.exports = router;
