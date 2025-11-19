// routes/boardTopics.js
const express = require("express");
const router = express.Router();
const pool = require("../models/db");
const { createAndEmit } = require("../controllers/notificationController");

// ============ FRIEND / MEMBER HELPERS ============

// ดึงรายชื่อ "เพื่อนที่ยังไม่ได้เป็นสมาชิก board นี้"
async function getFriendsNotInBoard(userId, boardId) {
  const q = await pool.query(
    `
    SELECT
      CASE
        WHEN fe.user_a = $1 THEN fe.user_b
        ELSE fe.user_a
      END AS friend_id,
      COALESCE(u.username, u.email) AS display_name
    FROM friend_edges fe
    JOIN users u
      ON u.id_user = CASE
        WHEN fe.user_a = $1 THEN fe.user_b
        ELSE fe.user_a
      END
    WHERE
      (fe.user_a = $1 OR fe.user_b = $1)
      AND fe.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1
        FROM board_members bm
        WHERE bm.board_id = $2
          AND bm.user_id = CASE
            WHEN fe.user_a = $1 THEN fe.user_b
            ELSE fe.user_a
          END
      )
    ORDER BY display_name ASC
    `,
    [userId, boardId]
  );
  return q.rows;
}

// เช็คว่า a กับ b เป็นเพื่อนกันไหม (ใช้ friend_edges จริง ๆ)
async function areFriends(a, b) {
  const q = await pool.query(
    `
    SELECT 1
    FROM friend_edges fe
    WHERE
      fe.status = 'accepted'
      AND (
        (fe.user_a = $1 AND fe.user_b = $2)
        OR
        (fe.user_a = $2 AND fe.user_b = $1)
      )
    LIMIT 1
    `,
    [a, b]
  );
  return q.rowCount > 0;
}

// role ของ user ใน board
async function getBoardMemberRole(boardId, userId) {
  const q = await pool.query(
    `SELECT role FROM board_members WHERE board_id = $1 AND user_id = $2`,
    [boardId, userId]
  );
  return q.rows[0]?.role || null;
}

// ============ GET /api/boards/:boardId/friends ============
// คืน list เพื่อนของ user ที่ยังไม่ได้อยู่ใน board นี้
router.get("/:boardId/friends", async (req, res) => {
  try {
    const boardId = req.params.boardId;
    const userId = parseInt(req.query.user_id, 10);

    if (!boardId || !Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: "invalid_params" });
    }

    const rows = await getFriendsNotInBoard(userId, boardId);
    const out = rows.map((r) => ({
      userId: r.friend_id,
      name: r.display_name,
    }));

    return res.json(out);
  } catch (e) {
    console.error("GET /api/boards/:boardId/friends error", e);
    return res.status(500).json({ error: "internal_error" });
  }
});

// ============ POST /api/boards/:boardId/invite ============
// body: { user_id: <เรา>, targetUserId (หรือ target_user_id): <เพื่อน>, role? }
router.post("/:boardId/invite", async (req, res) => {
  const boardId = String(req.params.boardId);
  const me = parseInt(req.body.user_id, 10);
  const targetUserId = parseInt(
    req.body.targetUserId ?? req.body.target_user_id,
    10
  );
  const role = req.body.role || "editor";

  if (!Number.isInteger(me) || !Number.isInteger(targetUserId)) {
    return res.status(400).json({ error: "missing_params" });
  }

  try {
    // 1) เราต้องเป็น owner ของ board นี้ก่อน
    const myRole = await getBoardMemberRole(boardId, me);
    if (myRole !== "owner") {
      return res.status(403).json({ error: "forbidden" });
    }

    // 2) เช็คว่าเป็นเพื่อนกันจริง ๆ
    const okFriend = await areFriends(me, targetUserId);
    if (!okFriend) {
      return res.status(400).json({ error: "not_friend" });
    }

    // 3) เพิ่มลง board_members (หรืออัปเดต role ถ้ามีอยู่แล้ว)
    await pool.query(
      `
      INSERT INTO board_members (board_id, user_id, role)
      VALUES ($1,$2,$3)
      ON CONFLICT (board_id, user_id)
      DO UPDATE SET role = EXCLUDED.role
      `,
      [boardId, targetUserId, role]
    );

    // 4) สร้าง notification ด้วย controller กลาง (มี board_id ด้วย)
    const msg = "เพื่อนของคุณเชิญคุณเข้าร่วมห้องโน้ต";
    await createAndEmit(req.app, {
      targetUserId: targetUserId, // คนที่ถูกเชิญ
      actorId: me,                // เรา (เจ้าของห้อง)
      action: "board_invite",
      verb: "board_invite",
      message: msg,
      postId: null,
      boardId: boardId,
    });

    // 5) แจ้งเตือนผ่าน Socket.io แยก event board_invited ไว้ด้วย (ถ้าใช้ใน client)
    const io = req.app.get("io");
    if (io) {
      io.to(`user:${targetUserId}`).emit("board_invited", {
        boardId,
        role,
        inviterId: me,
      });
    }

    res.json({ ok: true });
  } catch (e) {
    console.error("POST /api/boards/:boardId/invite error", e);
    res.status(500).json({ error: "internal_error" });
  }
});

// ============ TOPIC APIs ============

// ดึงหัวข้อทั้งหมดของ board
router.get("/:boardId/topics", async (req, res) => {
  const { boardId } = req.params;
  try {
    const result = await pool.query(
      `SELECT id, board_id, title, order_index, created_at
       FROM board_topics
       WHERE board_id = $1
       ORDER BY order_index, created_at`,
      [boardId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error("get topics error:", err);
    res.status(500).json({ message: "error getting topics" });
  }
});

// สร้างหัวข้อใหม่
router.post("/:boardId/topics", async (req, res) => {
  const { boardId } = req.params;
  const { title } = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO board_topics (id, board_id, title, order_index)
       VALUES (gen_random_uuid(), $1, $2, 0)
       RETURNING id, board_id, title, order_index, created_at`,
      [boardId, title]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("create topic error:", err);
    res.status(500).json({ message: "error creating topic" });
  }
});

module.exports = router;
