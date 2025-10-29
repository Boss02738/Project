// routes/purchases.js
const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');

const router = express.Router();

const pool = require('../models/db'); // pg pool ของโปรเจ็กต์คุณ
const { generatePromptPayPayload } = require('../utils/promptpay');

// === storage สำหรับ slip (เก็บเป็นไฟล์) ===
const uploadsDir = path.join(process.cwd(), 'uploads', 'slips');
fs.mkdirSync(uploadsDir, { recursive: true });

const upload = multer({
  dest: uploadsDir,
  limits: { fileSize: 25 * 1024 * 1024 }, // 25MB
});

// ---------- POST /api/purchases  (เริ่มคำสั่งซื้อ) ----------
router.post('/api/purchases', async (req, res) => {
  const { postId, buyerId, post_id, buyer_id } = req.body || {};
  const _postId  = Number(postId ?? post_id);
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

    // 2) ค่าแอดมิน (PromptPay)
    const setQ = await client.query(`SELECT promptpay_mobile FROM admin_settings WHERE id = 1`);
    const promptpayMobile = setQ.rows[0]?.promptpay_mobile;
    if (!promptpayMobile) {
      await client.query('ROLLBACK');
      return res.status(500).json({ error: 'admin_promptpay_missing' });
    }

    // 3) gen QR payload
    const amountSatang = Number(post.price_amount_satang);
    const amountBaht = (amountSatang / 100).toFixed(2);
    const qrPayload = generatePromptPayPayload(promptpayMobile, amountBaht);

    // 4) สร้างออเดอร์
    const ins = await client.query(
      `INSERT INTO purchases (post_id, buyer_id, seller_id, amount_satang, expires_at)
       VALUES ($1, $2, $3, $4, now() + interval '10 minutes')
       RETURNING id, amount_satang, expires_at`,
      [_postId, _buyerId, post.seller_id, amountSatang]
    );

    await client.query('COMMIT');

    const row = ins.rows[0];
    return res.status(201).json({
      id: row.id,
      amount_satang: row.amount_satang,
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

// ---------- GET /api/purchases/:id  (ดูรายละเอียดออเดอร์) ----------
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

// ---------- POST /api/purchases/:id/slip  (อัปโหลดสลิป) ----------
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

module.exports = router;
