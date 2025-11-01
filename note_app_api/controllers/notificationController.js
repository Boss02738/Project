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
 * สร้างแจ้งเตือนแล้วยิง Socket.IO ให้ผู้ใช้เป้าหมาย
 * @param {object} io - socket.io instance (req.app.get('io'))
 * @param {object} opt
 *   - userId     (required)
 *   - actorId    (optional)
 *   - postId     (optional)
 *   - action     (required) e.g. 'like'|'comment'|'purchase'|'system'
 *   - message    (optional) fallback = action
 */
async function createAndEmit(io, { userId, actorId, postId = null, action, message }) {
  if (!userId || !action) return { ok: false, error: 'invalid_args' };
  if (actorId && Number(actorId) === Number(userId)) {
    // ไม่แจ้งเตือนตัวเอง
    return { ok: false, skipped: 'self' };
  }

  const verb = actionToVerb(action);

  const ins = await pool.query(
    `INSERT INTO notifications (user_id, actor_id, post_id, action, message, verb)
     VALUES ($1,$2,$3,$4,$5,$6)
     RETURNING id, user_id, actor_id, post_id, action, verb, message, is_read, created_at`,
    [userId, actorId ?? null, postId ?? null, action, message || action, verb]
  );

  const row = ins.rows[0];

  // ยิง socket ไปหาห้อง user:${userId}
  io.to(`user:${userId}`).emit('notify', {
    id: row.id,
    action: row.action,
    verb: row.verb,
    message: row.message,
    post_id: row.post_id,
    actor_id: row.actor_id,
    created_at: row.created_at,
  });

  return { ok: true, row };
}

/** GET /api/notifications  (query: user_id, unread_only?, limit?, offset?) */
async function listNotifications(req, res) {
  try {
    const userId = Number(req.query.user_id);
    if (!userId) return res.status(400).json({ message: 'user_id required' });

    const unreadOnly = String(req.query.unread_only || 'false').toLowerCase() === 'true';
    const limit = Math.min(Number(req.query.limit) || 30, 100);
    const offset = Number(req.query.offset) || 0;

    const r = await pool.query(
      `
      SELECT n.id, n.user_id, n.actor_id, n.post_id, n.action, n.verb, n.message,
             n.is_read, n.created_at,
             COALESCE(a.username,'') AS actor_name,
             COALESCE(p.text,'')      AS post_text
      FROM notifications n
      LEFT JOIN users a ON a.id_user = n.actor_id
      LEFT JOIN posts p ON p.id      = n.post_id
      WHERE n.user_id = $1
        ${unreadOnly ? 'AND n.is_read = false' : ''}
      ORDER BY n.created_at DESC
      LIMIT $2 OFFSET $3
      `,
      [userId, limit, offset]
    );

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
      `SELECT COUNT(*)::int AS unread FROM notifications WHERE user_id=$1 AND is_read=false`,
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
      `UPDATE notifications SET is_read=true WHERE id=$1 AND user_id=$2 RETURNING id`,
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
      `UPDATE notifications SET is_read=true WHERE user_id=$1 AND is_read=false`,
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
