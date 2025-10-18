const express = require('express');
const router = express.Router();
const post = require('../controllers/postController');

router.get('/subject/:subject', post.getPostsBySubject); // ✅ /api/auth/subject/:subject
router.post('/posts', post.createPost);
router.get('/feed', post.getFeed);

router.post('/posts/:id/like', post.toggleLike);
router.get('/posts/:id/counts', post.getPostCounts);
router.get('/posts/:id/comments', post.getComments);
router.post('/posts/:id/comments', post.addComment);

router.post('/posts/:id/save', post.toggleSave);
router.get('/posts/:id/save/status', post.getSavedStatus);
router.get('/saved', post.getSavedPosts);


module.exports = router;
