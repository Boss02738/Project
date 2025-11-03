const express = require('express');
const router = express.Router();
const noti = require('../controllers/notificationController');

// ทั้งหมด “เป็น path สัมพัทธ์” แล้วค่อยไป mount ที่ /api/notifications ใน app.js
router.get('/', noti.listNotifications);            // /api/notifications
router.get('/unread-count', noti.getUnreadCount);   // /api/notifications/unread-count
router.post('/:id/mark-read', noti.markRead);       // /api/notifications/:id/mark-read
router.post('/mark-all-read', noti.markAllRead);    // /api/notifications/mark-all-read

module.exports = router;