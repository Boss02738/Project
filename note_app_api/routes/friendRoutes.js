const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/friendController");

// สร้างคำขอ (A → B)
router.post("/request", ctrl.sendRequest);

// ตอบคำขอ (accept / reject) — ผู้รับกด
router.post("/respond", ctrl.respondRequest);

// ยกเลิกคำขอ — ฝั่งผู้ส่งกดยกเลิก (ยัง pending)
router.post("/cancel", ctrl.cancelRequest);

// เลิกเป็นเพื่อน (ตอน status = accepted)
router.delete("/unfriend/:other_user_id", ctrl.unfriend);

// รายชื่อเพื่อน (accepted)
router.get("/list", ctrl.listFriends);

// คิวคำขอรอฉันตอบ / คำขอที่ฉันส่ง
router.get("/requests/incoming", ctrl.listIncoming);
router.get("/requests/outgoing", ctrl.listOutgoing);
router.get("/requests/incoming/count", ctrl.incomingCount);

// ตรวจสถานะระหว่างฉันกับอีกคน
router.get("/status", ctrl.getStatus);


module.exports = router;
