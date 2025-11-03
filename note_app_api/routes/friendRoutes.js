// routes/friendRoutes.js
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/friendController");

// ถ้าอยากเช็คว่าโหลดได้จริง ลองเปิดบรรทัดนี้ชั่วคราว:
// console.log("friendController keys:", Object.keys(ctrl));

router.post("/request", ctrl.sendRequest);
router.post("/respond", ctrl.respondRequest);
router.post("/cancel", ctrl.cancelRequest);

router.delete("/unfriend/:other_user_id", ctrl.unfriend);

router.get("/list", ctrl.listFriends);
router.get("/requests/incoming", ctrl.listIncoming);
router.get("/requests/outgoing", ctrl.listOutgoing);
router.get("/requests/incoming/count", ctrl.incomingCount);

router.get("/status", ctrl.getStatus);

module.exports = router;
