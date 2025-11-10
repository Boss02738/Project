const express = require('express');
const router = express.Router();
const noti = require('../controllers/notificationController');

router.get('/', noti.listNotifications);            
router.get('/unread-count', noti.getUnreadCount);   
router.post('/:id/mark-read', noti.markRead);       
router.post('/mark-all-read', noti.markAllRead);

module.exports = router;