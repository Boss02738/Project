// routes/withdrawals.js
const express = require('express');
const path   = require('path');
const fs     = require('fs');
const multer = require('multer');
const pool   = require('../models/db');

const router = express.Router();

/* ---------------- storage: uploads/withdraw_qr ---------------- */
const dir = path.join(process.cwd(), 'uploads', 'withdraw_qr');
fs.mkdirSync(dir, { recursive: true });

const upload = multer({
  dest: dir,
  limits: { fileSize: 25 * 1024 * 1024 },
});

/* ---------------- helpers ---------------- */
async function getCoinRate(client) {
  // ถ้าไม่มีค่าในตาราง admin_settings ให้ใช้ 100 สตางค์/เหรียญ
  const r = await client.query(
    `SELECT COALESCE(coin_rate_satang_per_coin, 100) AS rate
     FROM admin_settings WHERE id = 1`
  );
  return Number(r.rows[0]?.rate || 100);
}

/* ==============================================================
 * POST /api/withdrawals
 * form-data: user_id, coins, qr (file)
 * สร้างคำขอถอนสถานะ pending + หักเหรียญทันที
 * ==============================================================*/
router.post('/api/withdrawals', upload.single('qr'), async (req, res) => {
  const userId = Number(req.body?.user_id || 0);
  const coins  = Number(req.body?.coins   || 0);

  if (!userId || !Number.isFinite(coins) || coins <= 0) {
    return res.status(400).json({ error: 'invalid_params' });
  }
  if (!req.file) {
    return res.status(400).json({ error: 'missing_qr_file' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // lock แถวกระเป๋า และเช็คยอด
    const uw = await client.query(
      `SELECT coins FROM user_wallets WHERE user_id = $1 FOR UPDATE`,
      [userId]
    );
    const current = Number(uw.rows[0]?.coins || 0);
    if (current < coins) {
      throw new Error('insufficient_coins');
    }

    const rate          = await getCoinRate(client);
    const amountSatang  = coins * rate;
    const rel           = '/' + path.relative(process.cwd(), req.file.path).replace(/\\/g, '/');

    // หักเหรียญทันที
    await client.query(
      `UPDATE user_wallets
         SET coins = coins - $2, updated_at = now()
       WHERE user_id = $1`,
      [userId, coins]
    );

    // บันทึกธุรกรรม (ลบ)
    await client.query(
      `INSERT INTO wallet_transactions
        (user_id, type, amount_satang, coins, rate_satang_per_coin, note, created_at)
       VALUES ($1, 'debit_withdrawal', $2 * -1, $3 * -1, $4, 'withdraw request', now())`,
      [userId, amountSatang, coins, rate]
    );

    // บันทึกคำขอถอน
    const ins = await client.query(
      `INSERT INTO withdrawals
        (user_id, coins, rate_satang_per_coin, amount_satang, bank_qr_file, status, created_at)
       VALUES ($1, $2, $3, $4, $5, 'pending', now())
       RETURNING id, user_id, coins, rate_satang_per_coin, amount_satang, bank_qr_file, status, created_at`,
      [userId, coins, rate, amountSatang, rel]
    );

    await client.query('COMMIT');
    return res.status(201).json({ withdrawal: ins.rows[0] });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('create withdrawal error:', e);
    if (String(e.message) === 'insufficient_coins') {
      return res.status(400).json({ error: 'insufficient_coins' });
    }
    return res.status(500).json({ error: 'internal_error' });
  } finally {
    client.release();
  }
});

/* ==============================================================
 * GET /api/withdrawals/my?user_id=...
 * ==============================================================*/
router.get('/api/withdrawals/my', async (req, res) => {
  const userId = Number(req.query.user_id || 0);
  if (!userId) return res.status(400).json({ error: 'invalid_user' });

  try {
    const r = await pool.query(
      `SELECT id, user_id, coins, rate_satang_per_coin, amount_satang,
              bank_qr_file, status, admin_note, created_at, paid_at, rejected_at
       FROM withdrawals
       WHERE user_id = $1
       ORDER BY created_at DESC`,
      [userId]
    );
    return res.json({ items: r.rows });
  } catch (e) {
    console.error('get my withdrawals error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
});

/* ==============================================================
 * GET /api/admin/withdrawals/pending  (สำหรับหน้าแอดมิน)
 * ==============================================================*/
router.get('/api/admin/withdrawals/pending', async (_req, res) => {
  try {
    const r = await pool.query(
      `SELECT id, user_id, coins, rate_satang_per_coin, amount_satang,
              bank_qr_file, status, created_at
       FROM withdrawals
       WHERE status = 'pending'
       ORDER BY created_at DESC`
    );
    return res.json({ items: r.rows });
  } catch (e) {
    console.error('admin list withdrawals error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
});

/* ==============================================================
 * POST /api/admin/withdrawals/:id/approve
 * อนุมัติ: ไม่หักเหรียญซ้ำ (หักไปแล้วตอนยื่นคำขอ) แค่ปิดงานเป็น paid
 * ==============================================================*/
router.post('/api/admin/withdrawals/:id/approve', async (req, res) => {
  const id = Number(req.params.id || 0);
  const adminId = Number(req.body?.admin_id || 0);
  const note = String(req.body?.note || 'withdrawal paid');

  if (!id) return res.status(400).json({ error: 'invalid_id' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const wq = await client.query(
      `SELECT id, user_id, status FROM withdrawals WHERE id=$1 FOR UPDATE`,
      [id]
    );
    if (wq.rowCount === 0) throw new Error('not_found');
    const w = wq.rows[0];
    if (w.status !== 'pending') throw new Error('invalid_status');

    // เปลี่ยนสถานะเป็น paid (ไม่ปรับ wallet แล้ว)
    await client.query(
      `UPDATE withdrawals
         SET status='paid', admin_id=$2, admin_note=$3, paid_at=now()
       WHERE id=$1`,
      [id, adminId || null, note]
    );

    await client.query('COMMIT');
    return res.json({ ok: true, withdrawal_id: id });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('approve withdrawal error:', e);
    const msg = String(e.message || e);
    const code = msg === 'not_found' ? 404 :
                 msg === 'invalid_status' ? 400 : 500;
    return res.status(code).json({ error: msg });
  } finally {
    client.release();
  }
});

/* ==============================================================
 * POST /api/admin/withdrawals/:id/reject
 * ปฏิเสธ: คืนเหรียญให้ผู้ใช้ + บันทึกธุรกรรม refund_withdrawal
 * ==============================================================*/
router.post('/api/admin/withdrawals/:id/reject', async (req, res) => {
  const id = Number(req.params.id || 0);
  const adminId = Number(req.body?.admin_id || 0);
  const reason  = String(req.body?.reason || 'rejected');

  if (!id) return res.status(400).json({ error: 'invalid_id' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const wq = await client.query(
      `SELECT id, user_id, coins, rate_satang_per_coin, amount_satang, status
       FROM withdrawals WHERE id=$1 FOR UPDATE`,
      [id]
    );
    if (wq.rowCount === 0) throw new Error('not_found');
    const w = wq.rows[0];
    if (w.status !== 'pending') throw new Error('invalid_status');

    // คืนเหรียญ
    await client.query(
      `UPDATE user_wallets
         SET coins = coins + $2, updated_at = now()
       WHERE user_id = $1`,
      [w.user_id, w.coins]
    );

    await client.query(
      `INSERT INTO wallet_transactions
        (user_id, type, amount_satang, coins, rate_satang_per_coin, note, created_at)
       VALUES ($1, 'refund_withdrawal', $2, $3, $4, $5, now())`,
      [w.user_id, Number(w.amount_satang), Number(w.coins), Number(w.rate_satang_per_coin), reason]
    );

    await client.query(
      `UPDATE withdrawals
         SET status='rejected', admin_id=$2, admin_note=$3, rejected_at=now()
       WHERE id=$1`,
      [id, adminId || null, reason]
    );

    await client.query('COMMIT');
    return res.json({ ok: true, withdrawal_id: id });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('reject withdrawal error:', e);
    const msg = String(e.message || e);
    const code = msg === 'not_found' ? 404 :
                 msg === 'invalid_status' ? 400 : 500;
    return res.status(code).json({ error: msg });
  } finally {
    client.release();
  }
});

module.exports = router;
