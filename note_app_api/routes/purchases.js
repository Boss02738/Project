const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');

const router = express.Router();

const purchaseCtrl = require('../controllers/purchaseController');

const uploadsDir = path.join(process.cwd(), 'uploads', 'slips');
fs.mkdirSync(uploadsDir, { recursive: true });

const upload = multer({
  dest: uploadsDir,
  limits: { fileSize: 25 * 1024 * 1024 },
});

router.get('/:userId/posts', purchaseCtrl.listPurchasedPosts);   // รายการโพสต์ที่ซื้อแล้วของ user
router.post('/', purchaseCtrl.createPurchase);                   // สร้างรายการซื้อ + คืน QR
router.get('/:id', purchaseCtrl.getPurchase);                    // ดูสถานะคำสั่งซื้อ
router.post('/:id/slip', upload.single('slip'), purchaseCtrl.uploadSlip); // อัปโหลดสลิป + ตรวจอัตโนมัติ
router.post('/:id/approve', purchaseCtrl.approvePurchase);       // อนุมัติมือ
router.post('/:id/reject', purchaseCtrl.rejectPurchase);         // ปฏิเสธ

module.exports = router;
