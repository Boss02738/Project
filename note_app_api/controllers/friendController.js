const pool = require("../models/db");

// จัดคู่ให้ a<b เสมอ
function orderPair(u1, u2) {
  const a = Number(u1), b = Number(u2);
  return a < b ? [a, b] : [b, a];
}

// แปลงผลลัพธ์ status → สถานะที่ UI ใช้
function toUiStatus(row, currentUserId) {
  if (!row) return "none";
  const s = row.status;
  if (s === "accepted") return "friends";
  if (s === "pending") {
    if (row.initiator_id && Number(row.initiator_id) === Number(currentUserId)) return "pending_out";
    return "pending_in";
  }
  // rejected/canceled/blocked → ถือเป็น none (เริ่มใหม่ได้)
  return "none";
}

// สร้างคำขอเป็นเพื่อน
exports.sendRequest = async (req, res) => {
  const { from_user_id, to_user_id } = req.body || {};
  if (!from_user_id || !to_user_id) {
    return res.status(400).json({ message: "ต้องมี from_user_id และ to_user_id" });
  }
  if (Number(from_user_id) === Number(to_user_id)) {
    return res.status(400).json({ message: "ห้ามส่งคำขอถึงตัวเอง" });
  }

  const [a, b] = orderPair(from_user_id, to_user_id);
  try {
    // ดู row เดิม (ถ้ามี)
    const { rows } = await pool.query(
      `SELECT user_a, user_b, status, initiator_id FROM public.friend_edges
       WHERE user_a=$1 AND user_b=$2`,
      [a, b]
    );

    if (!rows.length) {
      // ยังไม่มี → แทรก pending
      await pool.query(
        `INSERT INTO public.friend_edges(user_a, user_b, status, initiator_id)
         VALUES($1,$2,'pending',$3)`,
        [a, b, from_user_id]
      );
      return res.json({ ok: true, status: "pending_out" });
    }

    const row = rows[0];

    if (row.status === "accepted") {
      return res.status(409).json({ message: "เป็นเพื่อนกันอยู่แล้ว" });
    }
    if (row.status === "pending") {
      // กันส่งซ้ำ
      return res.status(409).json({ message: "มีคำขอที่รอดำเนินการอยู่แล้ว" });
    }

    // เคยถูก reject/canceled มาก่อน → อนุญาตเริ่มใหม่
    await pool.query(
      `UPDATE public.friend_edges
       SET status='pending', initiator_id=$3, updated_at=NOW(), accepted_at=NULL
       WHERE user_a=$1 AND user_b=$2`,
      [a, b, from_user_id]
    );
    return res.json({ ok: true, status: "pending_out" });
  } catch (err) {
    console.error("sendRequest error:", err);
    res.status(500).json({ message: "ส่งคำขอล้มเหลว" });
  }
};

// ตอบคำขอ (accept/reject) — ผู้รับกด
exports.respondRequest = async (req, res) => {
  const { user_id, other_user_id, action } = req.body || {};
  if (!user_id || !other_user_id || !action) {
    return res.status(400).json({ message: "ต้องมี user_id, other_user_id, action" });
  }
  const act = String(action).toLowerCase();
  if (!["accept","reject"].includes(act)) {
    return res.status(400).json({ message: "action ต้องเป็น accept หรือ reject" });
  }

  const [a, b] = orderPair(user_id, other_user_id);
  try {
    const { rows } = await pool.query(
      `SELECT status, initiator_id FROM public.friend_edges
       WHERE user_a=$1 AND user_b=$2`,
      [a, b]
    );
    if (!rows.length || rows[0].status !== "pending") {
      return res.status(404).json({ message: "ไม่พบคำขอที่รอดำเนินการ" });
    }

    // ผู้รับต้องไม่ใช่ initiator
    if (Number(rows[0].initiator_id) === Number(user_id)) {
      return res.status(403).json({ message: "คุณเป็นผู้ส่งคำขอ ไม่สามารถตอบคำขอของตัวเอง" });
    }

    if (act === "reject") {
      await pool.query(
        `UPDATE public.friend_edges
         SET status='rejected', updated_at=NOW(), initiator_id=NULL
         WHERE user_a=$1 AND user_b=$2`,
        [a, b]
      );
      return res.json({ ok: true, status: "none" });
    }

    // accept
    await pool.query(
      `UPDATE public.friend_edges
       SET status='accepted', accepted_at=NOW(), updated_at=NOW(), initiator_id=NULL
       WHERE user_a=$1 AND user_b=$2`,
      [a, b]
    );
    return res.json({ ok: true, status: "friends" });
  } catch (err) {
    console.error("respondRequest error:", err);
    res.status(500).json({ message: "ตอบคำขอล้มเหลว" });
  }
};

// ยกเลิกคำขอ — ฝั่งผู้ส่ง
exports.cancelRequest = async (req, res) => {
  const { user_id, other_user_id } = req.body || {};
  if (!user_id || !other_user_id) {
    return res.status(400).json({ message: "ต้องมี user_id และ other_user_id" });
  }
  const [a, b] = orderPair(user_id, other_user_id);
  try {
    const { rows } = await pool.query(
      `SELECT status, initiator_id FROM public.friend_edges
       WHERE user_a=$1 AND user_b=$2`,
      [a, b]
    );
    if (!rows.length || rows[0].status !== "pending") {
      return res.status(404).json({ message: "ไม่มีคำขอ pending" });
    }
    if (Number(rows[0].initiator_id) !== Number(user_id)) {
      return res.status(403).json({ message: "คุณไม่ใช่ผู้ส่งคำขอ" });
    }
    await pool.query(
      `UPDATE public.friend_edges
       SET status='canceled', updated_at=NOW(), initiator_id=NULL
       WHERE user_a=$1 AND user_b=$2`,
      [a, b]
    );
    res.json({ ok: true, status: "none" });
  } catch (err) {
    console.error("cancelRequest error:", err);
    res.status(500).json({ message: "ยกเลิกคำขอล้มเหลว" });
  }
};

// เลิกเป็นเพื่อน
exports.unfriend = async (req, res) => {
  const { user_id } = req.query || {};
  const other = req.params.other_user_id;
  if (!user_id || !other) {
    return res.status(400).json({ message: "ต้องมี user_id และ other_user_id" });
  }
  const [a, b] = orderPair(user_id, other);
  try {
    const upd = await pool.query(
      `UPDATE public.friend_edges
       SET status='canceled', updated_at=NOW(), initiator_id=NULL
       WHERE user_a=$1 AND user_b=$2 AND status='accepted'`,
      [a, b]
    );
    if (!upd.rowCount) return res.status(404).json({ message: "ยังไม่ได้เป็นเพื่อนกัน" });
    res.json({ ok: true, status: "none" });
  } catch (err) {
    console.error("unfriend error:", err);
    res.status(500).json({ message: "เลิกเป็นเพื่อนล้มเหลว" });
  }
};

// รายชื่อเพื่อน (accepted)
exports.listFriends = async (req, res) => {
  const { user_id } = req.query || {};
  if (!user_id) return res.status(400).json({ message: "ต้องมี user_id" });

  const q = `
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
  `;
  try {
    const { rows } = await pool.query(q, [user_id]);
    res.json({ friends: rows });
  } catch (err) {
    console.error("listFriends error:", err);
    res.status(500).json({ message: "ดึงรายชื่อเพื่อนล้มเหลว" });
  }
};

// คิว incoming (รอฉันตอบ)
exports.listIncoming = async (req, res) => {
  const { user_id } = req.query || {};
  if (!user_id) return res.status(400).json({ message: "ต้องมี user_id" });

  const q = `
    SELECT fe.user_a, fe.user_b, fe.initiator_id, fe.created_at,
           CASE WHEN fe.user_a=$1 THEN fe.user_b ELSE fe.user_a END AS other_id,
           u.username, u.avatar_url
    FROM public.friend_edges fe
    JOIN public.users u
         ON u.id_user = CASE WHEN fe.user_a=$1 THEN fe.user_b ELSE fe.user_a END
    WHERE (fe.user_a=$1 OR fe.user_b=$1)
      AND fe.status='pending'
      AND fe.initiator_id <> $1
    ORDER BY fe.created_at DESC;
  `;
  try {
    const { rows } = await pool.query(q, [user_id]);
    res.json({ incoming: rows });
  } catch (err) {
    console.error("listIncoming error:", err);
    res.status(500).json({ message: "ดึง incoming ล้มเหลว" });
  }
};

// คิว outgoing (ฉันเป็นผู้ส่ง)
exports.listOutgoing = async (req, res) => {
  const { user_id } = req.query || {};
  if (!user_id) return res.status(400).json({ message: "ต้องมี user_id" });

  const q = `
    SELECT fe.user_a, fe.user_b, fe.initiator_id, fe.created_at,
           CASE WHEN fe.user_a=$1 THEN fe.user_b ELSE fe.user_a END AS other_id,
           u.username, u.avatar_url
    FROM public.friend_edges fe
    JOIN public.users u
         ON u.id_user = CASE WHEN fe.user_a=$1 THEN fe.user_b ELSE fe.user_a END
    WHERE (fe.user_a=$1 OR fe.user_b=$1)
      AND fe.status='pending'
      AND fe.initiator_id = $1
    ORDER BY fe.created_at DESC;
  `;
  try {
    const { rows } = await pool.query(q, [user_id]);
    res.json({ outgoing: rows });
  } catch (err) {
    console.error("listOutgoing error:", err);
    res.status(500).json({ message: "ดึง outgoing ล้มเหลว" });
  }
};

// ตรวจสถานะระหว่างฉันกับอีกคน
exports.getStatus = async (req, res) => {
  const { user_id, other_id } = req.query || {};
  if (!user_id || !other_id) {
    return res.status(400).json({ message: "ต้องมี user_id และ other_id" });
  }
  const [a, b] = orderPair(user_id, other_id);
  try {
    const { rows } = await pool.query(
      `SELECT status, initiator_id FROM public.friend_edges
       WHERE user_a=$1 AND user_b=$2`,
      [a, b]
    );
    const status = toUiStatus(rows[0], user_id);
    res.json({ status });
  } catch (err) {
    console.error("getStatus error:", err);
    res.status(500).json({ message: "เช็คสถานะล้มเหลว" });
  }
};

exports.incomingCount = async (req, res) => {
  const { user_id } = req.query || {};
  if (!user_id) return res.status(400).json({ message: "ต้องมี user_id" });
  try {
    const { rows } = await pool.query(
      `SELECT COUNT(*)::int AS cnt
       FROM public.friend_edges
       WHERE (user_a=$1 OR user_b=$1)
         AND status='pending'
         AND initiator_id <> $1`,
      [user_id]
    );
    res.json({ count: rows[0]?.cnt ?? 0 });
  } catch (e) {
    console.error("incomingCount error:", e);
    res.status(500).json({ message: "นับคำขอล้มเหลว" });
  }
};
