// controllers/notificationController.js
const pool = require('../models/db');

function actionToVerb(action) {
  switch (String(action || '').toLowerCase()) {
    case 'like':     return 'liked';
    case 'comment':  return 'commented';
    case 'purchase': return 'purchased';
    case 'system':   return 'notified';
    default:         return 'notified';
  }
}

/**
 * ใช้ได้ 2 แบบ:
 * 1) createAndEmit(io, { userId, actorId?, postId?, action, message? })
 * 2) createAndEmit({ userId, actorId?, postId?, action, message? })  // ไม่มี io
 */
async function createAndEmit(arg1, arg2) {
  try {
    // รองรับทั้งสอง signature
    let io = null;
    let opt = null;

    if (arg2 && typeof arg2 === 'object') {
      io = arg1 || null;
      opt = arg2;
    } else if (arg1 && typeof arg1 === 'object') {
      // กรณีเรียกแบบไม่มี io
      io = null;
      opt = arg1;
    }

    if (!opt || typeof opt !== 'object') {
      return { ok: false, error: 'invalid_args' };
    }

    // ดึงค่าพร้อมแปลงชนิดและ default
    const userId   = Number(opt.userId) || Number(opt.receiverId) || 0;
    const actorId  = opt.actorId == null ? null : Number(opt.actorId);
    const postId   = opt.postId == null ? null : Number(opt.postId);
    const action   = String(opt.action || opt.verb || '').trim().toLowerCase();
    const message  = (opt.message == null || String(opt.message).trim() === '')
      ? (action || 'notified')
      : String(opt.message).trim();

    // guard ขั้นพื้นฐาน
    if (!userId || !action) return { ok: false, error: 'invalid_args' };
    if (actorId && Number(actorId) === Number(userId)) {
      // ไม่แจ้งเตือนตัวเอง
      return { ok: false, skipped: 'self' };
    }

    const verb = actionToVerb(action);

    // INSERT ระบุชื่อคอลัมน์ชัดเจนกันสลับตำแหน่ง
    const ins = await pool.query(
      `INSERT INTO public.notifications
         (user_id, actor_id, post_id, action, message, verb, is_read, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,false, now())
       RETURNING id, user_id, actor_id, post_id, action, verb, message, is_read, created_at`,
      [userId, actorId, postId, action, message, verb]
    );

    const row = ins.rows[0];

    // ยิง socket ถ้ามี io
    try {
      if (io && typeof io.to === 'function') {
        io.to(`user:${userId}`).emit('notify', {
          id: row.id,
          action: row.action,
          verb: row.verb,
          message: row.message,
          post_id: row.post_id,
          actor_id: row.actor_id,
          created_at: row.created_at,
        });
      }
    } catch (e) {
      // ไม่ให้การส่ง socket ทำให้ endpoint พัง
      console.warn('socket emit failed:', e.message);
    }

    return { ok: true, row };
  } catch (e) {
    console.error('createAndEmit error:', e);
    return { ok: false, error: 'server_error' };
  }
}

/** GET /api/notifications  (query: user_id, unread_only?, limit?, offset?) */
async function listNotifications(req, res) {
  try {
    const userId = Number(req.query.user_id);
    if (!userId) return res.status(400).json({ message: 'user_id required' });

    const unreadOnly = String(req.query.unread_only || 'false').toLowerCase() === 'true';
    const limit  = Math.min(Number(req.query.limit) || 30, 100);
    const offset = Number(req.query.offset) || 0;

    const r = await pool.query(`
      SELECT
        n.id, n.user_id, n.actor_id, n.post_id, n.action, n.verb, n.message,
        n.is_read, n.created_at,

        /* ผู้กระทำ (ไว้แสดงรูปวงกลมซ้าย) */
        COALESCE(a.username,'') AS actor_name,
        COALESCE(a.avatar_url, '/uploads/avatars/default.png') AS actor_avatar,

        /* ข้อความโพสต์ + รูปแรกของโพสต์ (ไว้แสดงทางขวา) */
        COALESCE(p.text,'') AS post_text,
        (
          SELECT pi.image_url
          FROM post_images pi
          WHERE pi.post_id = n.post_id
          ORDER BY pi.id ASC
          LIMIT 1
        ) AS post_image

      FROM notifications n
      LEFT JOIN users a ON a.id_user = n.actor_id
      LEFT JOIN posts p ON p.id      = n.post_id
      WHERE n.user_id = $1
        ${unreadOnly ? 'AND n.is_read = false' : ''}
      ORDER BY n.created_at DESC
      LIMIT $2 OFFSET $3
    `, [userId, limit, offset]);

    res.json({ items: r.rows, limit, offset });
  } catch (e) {
    console.error('listNotifications error:', e);
    res.status(500).json({ message: 'server_error' });
  }
}

/** GET /api/notifications/unread-count?user_id= */
async function getUnreadCount(req, res) {
  try {
    const userId = Number(req.query.user_id);
    if (!userId) return res.status(400).json({ message: 'user_id required' });

    const r = await pool.query(
      `SELECT COUNT(*)::int AS unread FROM public.notifications WHERE user_id=$1 AND is_read=false`,
      [userId]
    );
    res.json({ unread: r.rows[0].unread });
  } catch (e) {
    console.error('getUnreadCount error:', e);
    res.status(500).json({ message: 'server_error' });
  }
}

/** POST /api/notifications/:id/read  body: { user_id } */
async function markRead(req, res) {
  try {
    const id = Number(req.params.id);
    const userId = Number(req.body.user_id);
    if (!id || !userId) return res.status(400).json({ message: 'id & user_id required' });

    const r = await pool.query(
      `UPDATE public.notifications SET is_read=true WHERE id=$1 AND user_id=$2 RETURNING id`,
      [id, userId]
    );
    if (r.rowCount === 0) return res.status(404).json({ message: 'not_found' });

    res.json({ ok: true });
  } catch (e) {
    console.error('markRead error:', e);
    res.status(500).json({ message: 'server_error' });
  }
}

/** POST /api/notifications/mark-all-read  body: { user_id } */
async function markAllRead(req, res) {
  try {
    const userId = Number(req.body.user_id);
    if (!userId) return res.status(400).json({ message: 'user_id required' });

    await pool.query(
      `UPDATE public.notifications SET is_read=true WHERE user_id=$1 AND is_read=false`,
      [userId]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error('markAllRead error:', e);
    res.status(500).json({ message: 'server_error' });
  }
}

module.exports = {
  listNotifications,
  getUnreadCount,
  markRead,
  markAllRead,
  createAndEmit,
};
