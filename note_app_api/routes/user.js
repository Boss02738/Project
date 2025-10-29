const express = require('express');
const router = express.Router();
const users = require('../controllers/usersController');
const wallet = require('../controllers/walletController');
const posts = require('../controllers/postController'); // จะเพิ่ม getPostDetail

router.get('/users/:id/purchased-posts', users.getPurchasedPosts);
router.get('/wallet/summary', wallet.getSummary);
router.post('/wallet/payout-request', wallet.createPayoutRequest);
router.get('/posts/:id/detail', posts.getPostDetail); // เพิ่มฟังก์ชันใน controller

module.exports = router;
