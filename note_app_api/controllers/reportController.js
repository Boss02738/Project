// Project/note_app_api/controllers/reportController.js
const pool = require('../models/db');

/* ---------- helper: run in transaction ---------- */
async function withTx(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    try { await client.query('ROLLBACK'); } catch {}
    throw e;
  } finally {
    client.release();
  }
}

/* =========================================================
 * POST /api/reports
 * body: { post_id, reporter_id, reason, details? }
 * - อนุญาตให้ผู้ใช้รายงาน 1 ครั้งต่อโพสต์ (อัปเดตรายละเอียดได้)
 * - ถ้าโพสต์ถูกแบนอยู่แล้ว จะไม่สร้างรายงานซ้ำ
 * =======================================================*/
exports.createReport = async (req, res) => {
  try {
    let { post_id, reporter_id, reason, details } = req.body || {};
    post_id = Number(post_id);
    reporter_id = Number(reporter_id);
    reason = String(reason || '').trim();
    details = (details ?? '').toString().trim();

    if (!post_id || !reporter_id || !reason) {
      return res.status(400).json({ message: 'post_id, reporter_id, reason are required' });
    }

    // ถ้าโพสต์ถูกแบนแล้ว ไม่ต้องรับรายงานใหม่
    const chk = await pool.query('SELECT is_banned FROM posts WHERE id=$1', [post_id]);
    if (!chk.rowCount) return res.status(404).json({ message: 'Post not found' });
    if (chk.rows[0].is_banned === true) {
      return res.status(200).json({ message: 'Post already banned; report ignored' });
    }

    // พยายาม UPSERT โดยยึดคู่ (reporter_id, post_id)
    const upsertSql = `
      INSERT INTO post_reports (post_id, reporter_id, reason, details)
      VALUES ($1,$2,$3, NULLIF($4,''))
      ON CONFLICT (reporter_id, post_id)
      DO UPDATE SET
        reason = EXCLUDED.reason,
        details = COALESCE(NULLIF(EXCLUDED.details,''), post_reports.details),
        status = 'pending',
        created_at = NOW()
      RETURNING *;
    `;
    let rows;
    try {
      ({ rows } = await pool.query(upsertSql, [post_id, reporter_id, reason, details]));
    } catch (e) {
      // เผื่อยังไม่มี unique index -> ลบรายการเก่าแล้วค่อยใส่ใหม่ (fallback)
      await pool.query(
        'DELETE FROM post_reports WHERE reporter_id=$1 AND post_id=$2',
        [reporter_id, post_id]
      );
      const ins = await pool.query(
        `INSERT INTO post_reports (post_id, reporter_id, reason, details)
         VALUES ($1,$2,$3,NULLIF($4,'')) RETURNING *;`,
        [post_id, reporter_id, reason, details]
      );
      rows = ins.rows;
    }

    return res.status(201).json({ message: 'Report submitted', report: rows[0] });
  } catch (err) {
    console.error('createReport error:', err);
    return res.status(500).json({ message: 'Server error' });
  }
};

/* =========================================================
 * GET /api/reports?status=pending|approved|rejected (default: pending)
 * - สำหรับแอดมินดึงคิวรายงาน
 * =======================================================*/
exports.listReports = async (req, res) => {
  try {
    const status = String(req.query.status || 'pending').toLowerCase();
    const q = `
      SELECT r.*,
             p.text        AS post_text,
             p.user_id     AS seller_id,
             p.is_banned   AS post_is_banned,
             -- รองรับ users.id หรือ users.id_user
             COALESCE(u.username, u2.username) AS reporter_name
      FROM post_reports r
      JOIN posts p ON p.id = r.post_id
      LEFT JOIN users u  ON u.id      = r.reporter_id
      LEFT JOIN users u2 ON u2.id_user = r.reporter_id
      WHERE r.status = $1
      ORDER BY r.created_at ASC
      LIMIT 200;
    `;
    const { rows } = await pool.query(q, [status]);
    return res.json({ items: rows });
  } catch (err) {
    console.error('listReports error:', err);
    return res.status(500).json({ message: 'Server error' });
  }
};

/* =========================================================
 * POST /api/reports/:id/resolve
 * body: { action: 'approve'|'reject', admin_id }
 * - approve: แบนโพสต์ + เปลี่ยนสถานะรายงาน
 * - reject : เปลี่ยนสถานะรายงานเป็น rejected
 * =======================================================*/
exports.resolveReport = async (req, res) => {
  const reportId = Number(req.params.id);
  let { action, admin_id } = req.body || {};
  admin_id = Number(admin_id);
  action = String(action || '').toLowerCase();

  if (!reportId || !admin_id || !['approve', 'reject'].includes(action)) {
    return res.status(400).json({ message: 'report id, admin_id and action(approve|reject) required' });
  }

  try {
    const out = await withTx(async (client) => {
      const r1 = await client.query(
        'SELECT id, post_id, status FROM post_reports WHERE id=$1 FOR UPDATE',
        [reportId]
      );
      if (!r1.rowCount) return { status: 404, body: { message: 'Report not found' } };
      const rep = r1.rows[0];

      if (rep.status !== 'pending') {
        return { status: 400, body: { message: 'Report already decided' } };
      }

      if (action === 'approve') {
        await client.query('UPDATE posts SET is_banned=TRUE WHERE id=$1', [rep.post_id]);
        await client.query(
          `UPDATE post_reports
             SET status='approved', reviewed_by=$1, reviewed_at=NOW()
           WHERE id=$2`,
          [admin_id, reportId]
        );
        return { status: 200, body: { ok: true, message: 'Report approved; post banned.' } };
      } else {
        await client.query(
          `UPDATE post_reports
             SET status='rejected', reviewed_by=$1, reviewed_at=NOW()
           WHERE id=$2`,
          [admin_id, reportId]
        );
        return { status: 200, body: { ok: true, message: 'Report rejected.' } };
      }
    });

    return res.status(out.status).json(out.body);
  } catch (err) {
    console.error('resolveReport error:', err);
    return res.status(500).json({ message: 'Server error' });
  }
};

/* ---------- Backward-compatible aliases (optional) ---------- */
// สำหรับ routes เก่า: GET /api/reports/pending , POST /api/reports/:id/decision
exports.listPending   = (req, res) => { req.query.status = 'pending'; return exports.listReports(req, res); };
exports.decideReport  = (req, res) => exports.resolveReport(req, res);
