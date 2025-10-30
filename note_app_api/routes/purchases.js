// routes/purchases.js
const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');

const router = express.Router();

const pool = require('../models/db');
const { generatePromptPayPayload } = require('../utils/promptpay');

// === storage สำหรับ slip (เก็บเป็นไฟล์) ===
const uploadsDir = path.join(process.cwd(), 'uploads', 'slips');
fs.mkdirSync(uploadsDir, { recursive: true });

const upload = multer({
  dest: uploadsDir,
  limits: { fileSize: 25 * 1024 * 1024 },
});

/* ---------------------------- helpers ---------------------------- */

async function getCoinRate(client) {
  const r = await client.query(
    `SELECT COALESCE(coin_rate_satang_per_coin, 100) AS rate
     FROM admin_settings WHERE id = 1`
  );
  const rate = Number(r.rows[0]?.rate || 0);
  if (!rate) throw new Error('rate_not_configured');
  return rate;
}

function buildPromptPayPayload(promptpayMobile, amountBahtNum) {
  try {
    return generatePromptPayPayload({
      target: String(promptpayMobile),
      amount: Number(amountBahtNum),
    });
  } catch (_) {
    const amtStr = Number(amountBahtNum).toFixed(2);
    return generatePromptPayPayload(String(promptpayMobile), amtStr);
  }
}

/* -------------------- POST /api/purchases (เริ่มออเดอร์) -------------------- */
router.post('/api/purchases', async (req, res) => {
  const { postId, buyerId, post_id, buyer_id } = req.body || {};
  const _postId = Number(postId ?? post_id);
  const _buyerId = Number(buyerId ?? buyer_id);

  if (!_postId || !_buyerId) {
    return res.status(400).json({ error: 'missing_required', details: { postId, buyerId } });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1) โหลดโพสต์
    const postQ = await client.query(
      `SELECT id, user_id AS seller_id, price_type, price_amount_satang
       FROM posts WHERE id = $1 FOR UPDATE`,
      [_postId]
    );
    if (postQ.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'post_not_found' });
    }
    const post = postQ.rows[0];

    if (post.price_type !== 'paid' || !post.price_amount_satang || post.price_amount_satang <= 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'post_not_paid' });
    }
    if (post.seller_id === _buyerId) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'buyer_is_seller' });
    }

    // 2) เบอร์พร้อมเพย์แอดมิน
    const setQ = await client.query(
      `SELECT promptpay_mobile FROM admin_settings WHERE id = 1`
    );
    const promptpayMobile = setQ.rows[0]?.promptpay_mobile;
    if (!promptpayMobile) {
      await client.query('ROLLBACK');
      return res.status(500).json({ error: 'admin_promptpay_missing' });
    }

    // 3) gen EMVCo payload
    const amountSatang = Number(post.price_amount_satang);
    const amountBahtNum = amountSatang / 100;
    const qrPayload = buildPromptPayPayload(promptpayMobile, amountBahtNum);

    // 4) สร้างออเดอร์ (ระบุ status='pending' ให้ชัด)
    const ins = await client.query(
      `INSERT INTO purchases (post_id, buyer_id, seller_id, amount_satang, status, expires_at)
       VALUES ($1, $2, $3, $4, 'pending', now() + interval '10 minutes')
       RETURNING id, amount_satang, status, expires_at`,
      [_postId, _buyerId, post.seller_id, amountSatang]
    );

    await client.query('COMMIT');

    const row = ins.rows[0];
    return res.status(201).json({
      id: row.id,
      amount_satang: row.amount_satang,
      status: row.status,
      qr_payload: qrPayload,
      expires_at: row.expires_at,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('create purchase error:', err);
    return res.status(500).json({ error: 'internal_error' });
  } finally {
    client.release();
  }
});

/* -------------------- GET /api/purchases/:id -------------------- */
router.get('/api/purchases/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!id) return res.status(400).json({ error: 'invalid_id' });

  try {
    const q = await pool.query(
      `SELECT id, post_id, buyer_id, seller_id, amount_satang, status, expires_at, created_at
       FROM purchases WHERE id = $1`,
      [id]
    );
    if (q.rowCount === 0) return res.status(404).json({ error: 'not_found' });
    return res.json({ purchase: q.rows[0] });
  } catch (e) {
    console.error('get purchase error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
});

/* ----------------- POST /api/purchases/:id/slip ---------------- */
router.post('/api/purchases/:id/slip', upload.single('slip'), async (req, res) => {
  const id = Number(req.params.id);
  if (!id) return res.status(400).json({ error: 'invalid_id' });
  if (!req.file) return res.status(400).json({ error: 'missing_file' });

  try {
    const relPath = path.relative(process.cwd(), req.file.path);
    await pool.query(
      `INSERT INTO payment_slips (purchase_id, file_path) VALUES ($1, $2)`,
      [id, `/${relPath.replace(/\\/g, '/')}`]
    );
    return res.json({ ok: true, file: `/${relPath.replace(/\\/g, '/')}` });
  } catch (e) {
    console.error('upload slip error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
});

/* --------------- POST /api/purchases/:id/approve (ADMIN) --------------- */
router.post('/api/purchases/:id/approve', async (req, res) => {
  const id = Number(req.params.id);
  const adminId = Number(req.body?.admin_id || 0);
  const note = String(req.body?.note || 'sale income');

  if (!id) return res.status(400).json({ error: 'invalid_id' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const pq = await client.query(
      `SELECT id, post_id, buyer_id, seller_id, amount_satang, status
       FROM purchases WHERE id = $1 FOR UPDATE`,
      [id]
    );
    if (pq.rowCount === 0) throw new Error('purchase_not_found');
    const pur = pq.rows[0];
    if (pur.status !== 'pending') throw new Error('invalid_status');

    const rate = await getCoinRate(client);
    const amountSatang = Number(pur.amount_satang);
    const coins = Math.floor(amountSatang / rate);

    // debug logs (ช่วยไล่ถ้าติด)
    console.log('[approve]', { id, adminId, amountSatang, rate, coins });

    if (!Number.isFinite(coins) || coins <= 0) {
      throw new Error('calculated_coins_is_zero'); // กันเคสราคา < rate
    }

    await client.query(
      `INSERT INTO purchased_posts (post_id, user_id, purchase_id)
       VALUES ($1, $2, $3)
       ON CONFLICT DO NOTHING`,
      [pur.post_id, pur.buyer_id, id]
    );

    await client.query(
      `INSERT INTO user_wallets (user_id, coins, updated_at)
       VALUES ($1, $2, now())
       ON CONFLICT (user_id) DO UPDATE
         SET coins = user_wallets.coins + EXCLUDED.coins,
             updated_at = now()`,
      [pur.seller_id, coins]
    );

    await client.query(
      `INSERT INTO wallet_transactions
       (user_id, type, amount_satang, coins, rate_satang_per_coin, related_purchase_id, note, created_at)
       VALUES ($1, 'credit_purchase', $2, $3, $4, $5, $6, now())`,
      [pur.seller_id, amountSatang, coins, rate, id, note]
    );

    await client.query(
      `UPDATE purchases
       SET status='approved', admin_id=$2, approved_at=now()
       WHERE id=$1`,
      [id, adminId || null]
    );

    await client.query('COMMIT');

    return res.json({
      ok: true,
      purchase_id: id,
      seller_id: pur.seller_id,
      credited_coins: coins,
      rate_satang_per_coin: rate,
    });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('approve purchase error:', e);
    const msg = String(e.message || e);
    const code =
      msg === 'purchase_not_found' ? 404 :
      msg === 'invalid_status' ? 400 :
      msg === 'rate_not_configured' ? 500 :
      msg === 'calculated_coins_is_zero' ? 400 : 500;
    return res.status(code).json({ error: msg });
  } finally {
    client.release();
  }
});

/* --------------- POST /api/purchases/:id/reject (ADMIN) --------------- */
router.post('/api/purchases/:id/reject', async (req, res) => {
  const id = Number(req.params.id);
  const adminId = Number(req.body?.admin_id || 0);
  const reason = String(req.body?.reason || 'rejected');

  if (!id) return res.status(400).json({ error: 'invalid_id' });

  try {
    const r = await pool.query(
      `UPDATE purchases
       SET status='rejected', admin_id=$2, admin_note=$3, rejected_at=now()
       WHERE id=$1 AND status='pending'
       RETURNING id`,
      [id, adminId || null, reason]
    );
    if (r.rowCount === 0)
      return res.status(400).json({ error: 'invalid_status_or_not_found' });
    return res.json({ ok: true, purchase_id: id });
  } catch (e) {
    console.error('reject purchase error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
