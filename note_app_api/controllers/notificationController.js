// controllers/notificationController.js
const pool = require("../models/db");

async function createAndEmit(app, payload) {
  const {
    targetUserId,
    actorId,
    action,
    message,
    postId = null,
    boardId = null, // ✅ เพิ่มรองรับ boardId
  } = payload || {};

  if (!targetUserId || !actorId || !action) {
    throw new Error("missing fields for notification");
  }

  // ✅ บันทึก board_id ลง table ด้วย
  const ins = await pool.query(
    `INSERT INTO public.notifications
       (user_id, actor_id, verb, action, message, post_id, board_id, is_read)
     VALUES ($1,$2,$3,$3,$4,$5,$6,false)
     RETURNING id, user_id, actor_id, verb, action, message,
               post_id, board_id, is_read, created_at`,
    [targetUserId, actorId, action, message || "", postId, boardId]
  );
  const row = ins.rows[0];

  // ดึงข้อมูล actor + รูป
  const q = await pool.query(
    `
    SELECT n.id, n.user_id, n.actor_id, n.verb, n.action,
           n.message, n.post_id, n.board_id, n.is_read, n.created_at,
           a.username AS actor_name,
           COALESCE(a.avatar_url,'') AS actor_avatar,
           (SELECT pi.image_url
              FROM public.post_images pi
             WHERE n.post_id IS NOT NULL AND pi.post_id = n.post_id
             ORDER BY pi.id ASC
             LIMIT 1) AS post_image
      FROM public.notifications n
      JOIN public.users a ON a.id_user = n.actor_id
     WHERE n.id = $1
    `,
    [row.id]
  );
  const item = q.rows[0] || row;

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
      SELECT n.id, n.user_id, n.actor_id, n.verb, n.action,
             n.message, n.post_id, n.board_id, n.is_read, n.created_at,
             a.username AS actor_name,
             COALESCE(a.avatar_url,'') AS actor_avatar,
             (SELECT pi.image_url
                FROM public.post_images pi
               WHERE n.post_id IS NOT NULL AND pi.post_id = n.post_id
               ORDER BY pi.id ASC
               LIMIT 1) AS post_image
        FROM public.notifications n
        JOIN public.users a ON a.id_user = n.actor_id
       WHERE n.user_id = $1
       ORDER BY n.created_at DESC
       LIMIT $2
      `,
      [userId, limit]
    );
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
      `SELECT COUNT(*)::int AS unread
         FROM public.notifications
        WHERE user_id=$1 AND is_read=false`,
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
      `UPDATE public.notifications
          SET is_read=true
        WHERE id=$1 AND user_id=$2`,
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
      `UPDATE public.notifications
          SET is_read=true
        WHERE user_id=$1 AND is_read=false`,
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
