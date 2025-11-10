const pool = require("../models/db");
const { createAndEmit } = require("./notificationController");

function orderPair(a, b) {
  const x = Number(a),
    y = Number(b);
  return x < y ? [x, y] : [y, x];
}
async function findEdge(a, b) {
  const [ua, ub] = orderPair(a, b);
  const { rows } = await pool.query(
    `SELECT * FROM public.friend_edges WHERE user_a=$1 AND user_b=$2`,
    [ua, ub]
  );
  return rows[0] || null;
}
function edgeStatusForViewer(edge, viewerId, otherId) {
  if (!edge) return "none";
  const s = edge.status;
  if (s === "accepted") return "friends";
  if (s === "canceled" || s === "rejected") return "none";
  if (s === "pending") {
    if (edge.initiator_id === viewerId) return "pending_out";
    if (edge.initiator_id === otherId) return "pending_in";
    return "pending_in";
  }
  return "none";
}

async function getStatus(req, res) {
  try {
    const userId = Number(req.query.user_id);
    const otherId = Number(req.query.other_id);
    if (!userId || !otherId)
      return res.status(400).json({ message: "bad_request" });
    if (userId === otherId) return res.json({ status: "self" });
    const edge = await findEdge(userId, otherId);
    return res.json({ status: edgeStatusForViewer(edge, userId, otherId) });
  } catch (e) {
    console.error("getStatus", e);
    res.status(500).json({ message: "internal_error" });
  }
}

async function sendRequest(req, res) {
  const { from_user_id, to_user_id } = req.body || {};
  const fromId = Number(from_user_id),
    toId = Number(to_user_id);
  if (!fromId || !toId || fromId === toId)
    return res.status(400).json({ message: "bad_request" });
  try {
    const [ua, ub] = orderPair(fromId, toId);
    const now = new Date();
    const edge = await findEdge(fromId, toId);

    if (!edge) {
      await pool.query(
        `INSERT INTO public.friend_edges (user_a, user_b, status, initiator_id, created_at, updated_at)
         VALUES ($1,$2,'pending',$3,$4,$4)`,
        [ua, ub, fromId, now]
      );
    } else if (edge.status === "accepted") {
      return res.json({ ok: true, status: "friends" });
    } else {
      await pool.query(
        `UPDATE public.friend_edges
           SET status='pending', initiator_id=$3, updated_at=$4, accepted_at=NULL
         WHERE user_a=$1 AND user_b=$2`,
        [ua, ub, fromId, now]
      );
    }

    await createAndEmit(req.app, {
      targetUserId: toId,
      actorId: fromId,
      action: "friend_request",
      message: "ส่งคำขอเป็นเพื่อนถึงคุณ",
      postId: null,
    });

    return res.json({ ok: true, status: "pending_out" });
  } catch (e) {
    console.error("sendRequest", e);
    res.status(500).json({ message: "internal_error" });
  }
}

async function respondRequest(req, res) {
  const { user_id, other_user_id, action } = req.body || {};
  const me = Number(user_id),
    other = Number(other_user_id);
  if (!me || !other || me === other)
    return res.status(400).json({ message: "bad_request" });
  if (!["accept", "reject"].includes(String(action)))
    return res.status(400).json({ message: "invalid_action" });

  try {
    const [ua, ub] = orderPair(me, other);
    const edge = await findEdge(me, other);
    if (!edge || edge.status !== "pending")
      return res.status(404).json({ message: "no_pending_request" });
    if (edge.initiator_id === me)
      return res.status(403).json({ message: "initiator_cannot_respond" });

    const now = new Date();
    if (action === "accept") {
      await pool.query(
        `UPDATE public.friend_edges
           SET status='accepted', accepted_at=$3, updated_at=$3
         WHERE user_a=$1 AND user_b=$2`,
        [ua, ub, now]
      );

      await createAndEmit(req.app, {
        targetUserId: other,
        actorId: me,
        action: "friend_accept",
        message: "คำขอเป็นเพื่อนของคุณได้รับการยอมรับแล้ว",
        postId: null,
      });

      return res.json({ ok: true, status: "friends" });
    } else {
      await pool.query(
        `UPDATE public.friend_edges
           SET status='rejected', updated_at=$3
         WHERE user_a=$1 AND user_b=$2`,
        [ua, ub, now]
      );
      return res.json({ ok: true, status: "none" });
    }
  } catch (e) {
    console.error("respondRequest", e);
    res.status(500).json({ message: "internal_error" });
  }
}

async function cancelRequest(req, res) {
  const { user_id, other_user_id } = req.body || {};
  const me = Number(user_id),
    other = Number(other_user_id);
  if (!me || !other || me === other)
    return res.status(400).json({ message: "bad_request" });

  try {
    const [ua, ub] = orderPair(me, other);
    const edge = await findEdge(me, other);
    if (!edge || edge.status !== "pending" || edge.initiator_id !== me) {
      return res.status(404).json({ message: "no_pending_out" });
    }
    await pool.query(
      `UPDATE public.friend_edges SET status='canceled', updated_at=now()
       WHERE user_a=$1 AND user_b=$2`,
      [ua, ub]
    );
    return res.json({ ok: true, status: "none" });
  } catch (e) {
    console.error("cancelRequest", e);
    res.status(500).json({ message: "internal_error" });
  }
}

async function unfriend(req, res) {
  const me = Number(req.query.user_id);
  const other = Number(req.params.other_user_id);
  if (!me || !other || me === other)
    return res.status(400).json({ message: "bad_request" });

  try {
    const [ua, ub] = orderPair(me, other);
    const edge = await findEdge(me, other);
    if (!edge || edge.status !== "accepted") {
      return res.status(404).json({ message: "not_friends" });
    }
    await pool.query(
      `UPDATE public.friend_edges SET status='canceled', updated_at=now()
       WHERE user_a=$1 AND user_b=$2`,
      [ua, ub]
    );
    return res.json({ ok: true, status: "none" });
  } catch (e) {
    console.error("unfriend", e);
    res.status(500).json({ message: "internal_error" });
  }
}

/* ---------------- lists ---------------- */
async function listFriends(req, res) {
  const me = Number(req.query.user_id);
  if (!me) return res.status(400).json({ message: "bad_request" });
  try {
    const { rows } = await pool.query(
      `
      SELECT
      u.id_user,
      u.username,
      COALESCE(u.avatar_url, '/uploads/avatars/default.png') AS avatar_url,
      COALESCE(u.bio, '') AS bio
    FROM public.friend_edges fe
    JOIN public.users u
      ON u.id_user = CASE WHEN fe.user_a = $1 THEN fe.user_b ELSE fe.user_a END
    WHERE (fe.user_a = $1 OR fe.user_b = $1)
      AND fe.status = 'accepted'
    ORDER BY u.username NULLS LAST, u.id_user
      `,
      [me]
    );
    res.json({ friends: rows });
  } catch (e) {
    console.error("listFriends", e);
    res.status(500).json({ message: "internal_error" });
  }
}

async function listIncoming(req, res) {
  const me = Number(req.query.user_id);
  if (!me) return res.status(400).json({ message: "bad_request" });
  try {
    const { rows } = await pool.query(
      `
      SELECT CASE WHEN user_a=$1 THEN user_b ELSE user_a END AS other_id,
             status, initiator_id, created_at, updated_at
        FROM public.friend_edges
       WHERE status='pending' AND (user_a=$1 OR user_b=$1) AND initiator_id <> $1
       ORDER BY created_at DESC
      `,
      [me]
    );
    res.json({ incoming: rows });
  } catch (e) {
    console.error("listIncoming", e);
    res.status(500).json({ message: "internal_error" });
  }
}
async function listOutgoing(req, res) {
  const me = Number(req.query.user_id);
  if (!me) return res.status(400).json({ message: "bad_request" });
  try {
    const { rows } = await pool.query(
      `
      SELECT CASE WHEN user_a=$1 THEN user_b ELSE user_a END AS other_id,
             status, initiator_id, created_at, updated_at
        FROM public.friend_edges
       WHERE status='pending' AND (user_a=$1 OR user_b=$1) AND initiator_id = $1
       ORDER BY created_at DESC
      `,
      [me]
    );
    res.json({ outgoing: rows });
  } catch (e) {
    console.error("listOutgoing", e);
    res.status(500).json({ message: "internal_error" });
  }
}
async function incomingCount(req, res) {
  const me = Number(req.query.user_id);
  if (!me) return res.status(400).json({ message: "bad_request" });
  try {
    const { rows } = await pool.query(
      `
      SELECT COUNT(*)::int AS n
        FROM public.friend_edges
       WHERE status='pending' AND (user_a=$1 OR user_b=$1) AND initiator_id <> $1
      `,
      [me]
    );
    res.json({ count: rows[0]?.n ?? 0 });
  } catch (e) {
    console.error("incomingCount", e);
    res.status(500).json({ message: "internal_error" });
  }
}

module.exports = {
  getStatus,
  sendRequest,
  respondRequest,
  cancelRequest,
  unfriend,
  listFriends,
  listIncoming,
  listOutgoing,
  incomingCount,
};
