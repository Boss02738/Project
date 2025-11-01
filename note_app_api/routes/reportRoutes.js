// Project/note_app_api/routes/reportRoutes.js
const express = require('express');
const router = express.Router();

const ctrl = require('../controllers/reportController');

// ---------- User: ส่งรายงาน ----------
// POST  /api/reports
router.post('/', ctrl.createReport);

// ---------- Admin: ดูรายการ (รับ ?status=pending|approved|rejected) ----------
// GET   /api/reports
router.get('/', ctrl.listReports);

// ---------- Admin: ตัดสินรายงาน ----------
// POST  /api/reports/:id/resolve   body: { action: "approve" | "reject", admin_id }
router.post('/:id/resolve', ctrl.resolveReport);

/* (ออปชัน) รองรับเส้นทางเก่าเพื่อความเข้ากันได้เดิม
   GET  /api/reports/pending
   POST /api/reports/:id/decision
*/
router.get('/pending', ctrl.listPending);
router.post('/:id/decision', ctrl.decideReport);

module.exports = router;
