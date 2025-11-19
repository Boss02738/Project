// controllers/notificationController.js
const pool = require("../models/db");

/**
 * สร้าง notification แล้วยิง Socket.io ไปหา user เป้าหมาย
 *
 * payload:
 *  - targetUserId  (required)  : คนที่ "ได้รับ" noti
 *  - actorId       (required)  : คนที่เป็นคนทำ action
 *  - action        (required)  : เช่น 'like', 'comment', 'board_invite'
 *  - verb          (optional)  : ถ้าไม่ส่ง จะใช้ค่าเดียวกับ action
 *  - message       (optional)  : ข้อความแจ้งเตือน
 *  - postId        (optional)  : ผูกกับโพสต์ (กรณีไลก์/คอมเมนต์)
 *  - boardId       (optional)  : ผูกกับห้องโน้ต (กรณีเชิญเข้าห้อง)
 */
async function createAndEmit(app, payload) {
  const {
    targetUserId,
    actorId,
    action,
    verb,
    message,
    postId = null,
    boardId = null,
  } = payload || {};

  if (!targetUserId || !actorId || !action) {
    throw new Error("missing fields for notification");
  }

  const finalVerb = verb || action;

  // --- INSERT: เพิ่ม board_id เข้าไปด้วยแล้ว ---
  const ins = await pool.query(
    `INSERT INTO public.notifications
       (user_id, actor_id, verb, action, message, post_id, board_id, is_read)
     VALUES ($1,$2,$3,$4,$5,$6,$7,false)
     RETURNING id, user_id, actor_id, verb, action, message, post_id, board_id, is_read, created_at`,
    [targetUserId, actorId, finalVerb, action, message || "", postId, boardId]
  );
  const row = ins.rows[0];

  // ดึงข้อมูลที่ join users + post_images + boards ให้ครบ ใช้ส่งไปหน้าแอป
  const q = await pool.query(
    `
    SELECT
      n.id,
      n.user_id,
      n.actor_id,
      n.verb,
      n.action,
      n.message,
      n.post_id,
      n.board_id,
      n.is_read,
      n.created_at,
      a.username AS actor_name,
      COALESCE(a.avatar_url,'') AS actor_avatar,
      (SELECT pi.image_url
         FROM public.post_images pi
        WHERE n.post_id IS NOT NULL
          AND pi.post_id = n.post_id
        ORDER BY pi.id ASC
        LIMIT 1) AS post_image,
      b.name AS board_name
    FROM public.notifications n
    JOIN public.users a
      ON a.id_user = n.actor_id
    LEFT JOIN boards b
      ON b.id = n.board_id
    WHERE n.id = $1
    `,
    [row.id]
  );
  const item = q.rows[0] || row;

  // ยิง socket ไปหาผู้ใช้
  try {
    const io = app.get("io");
    if (io) {
      io.to(`user:${targetUserId}`).emit("notification:new", item);
    }
  } catch (e) {
    console.warn("emit notification failed:", e);
  }

  return item;
}

async function listNotifications(req, res) {
  try {
    const userId = Number(req.query.user_id);
    const limit = Math.min(Number(req.query.limit) || 50, 100);
    if (!userId) return res.status(400).json({ message: "bad_request" });

    const { rows } = await pool.query(
      `
      SELECT
        n.id,
        n.user_id,
        n.actor_id,
        n.verb,
        n.action,
        n.message,
        n.post_id,
        n.board_id,
        n.is_read,
        n.created_at,
        a.username AS actor_name,
        COALESCE(a.avatar_url,'') AS actor_avatar,
        (SELECT pi.image_url
           FROM public.post_images pi
          WHERE n.post_id IS NOT NULL
            AND pi.post_id = n.post_id
          ORDER BY pi.id ASC
          LIMIT 1) AS post_image,
        b.name AS board_name
      FROM public.notifications n
      JOIN public.users a
        ON a.id_user = n.actor_id
      LEFT JOIN boards b
        ON b.id = n.board_id
      WHERE n.user_id = $1
      ORDER BY n.created_at DESC
      LIMIT $2
      `,
      [userId, limit]
    );
    // ส่งออกเหมือนเดิม แต่ตอนนี้แต่ละ item จะมี board_id / board_name เพิ่มมาด้วย
    res.json({ items: rows });
  } catch (e) {
    console.error("listNotifications", e);
    res.status(500).json({ message: "internal_error" });
  }
}

async function getUnreadCount(req, res) {
  try {
    const userId = Number(req.query.user_id);
    if (!userId) return res.status(400).json({ message: "bad_request" });
    const { rows } = await pool.query(
      `SELECT COUNT(*)::int AS unread FROM public.notifications WHERE user_id=$1 AND is_read=false`,
      [userId]
    );
    res.json({ unread: rows[0]?.unread || 0 });
  } catch (e) {
    console.error("getUnreadCount", e);
    res.status(500).json({ message: "internal_error" });
  }
}

async function markRead(req, res) {
  try {
    const id = Number(req.params.id);
    const userId = Number(req.body.user_id);
    if (!id || !userId) return res.status(400).json({ message: "bad_request" });
    await pool.query(
      `UPDATE public.notifications SET is_read=true WHERE id=$1 AND user_id=$2`,
      [id, userId]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error("markRead", e);
    res.status(500).json({ message: "internal_error" });
  }
}

async function markAllRead(req, res) {
  try {
    const userId = Number(req.body.user_id || req.query.user_id);
    if (!userId) return res.status(400).json({ message: "bad_request" });
    await pool.query(
      `UPDATE public.notifications SET is_read=true WHERE user_id=$1 AND is_read=false`,
      [userId]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error("markAllRead", e);
    res.status(500).json({ message: "internal_error" });
  }
}

module.exports = {
  createAndEmit,
  listNotifications,
  getUnreadCount,
  markRead,
  markAllRead,
};
