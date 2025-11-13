// controllers/purchaseController.js
const pool = require('../models/db');
const QRCode = require('qrcode');
const path = require('path');
const { verifySlip } = require('../utils/slipVerifier');
const { generatePromptPayPayload } = require('../utils/promptpay'); // ใช้ตัวจริง

const TEN_MINUTES_MS = 10 * 60 * 1000;
const ADMIN_MOBILE = (process.env.ADMIN_PROMPTPAY_PHONE || '').replace(/\D/g, '');
const SLIP_TOLERANCE_PERCENT = Number(process.env.SLIP_TOLERANCE_PERCENT || 10);

/** ดึงเรตแปลงสตางค์ → เหรียญ จาก admin_settings */
async function getCoinRate(clientOrPool) {
  const r = await clientOrPool.query(
    `SELECT COALESCE(coin_rate_satang_per_coin, 100) AS rate
       FROM admin_settings WHERE id = 1`
  );
  return Number(r.rows[0]?.rate || 100);
}

/** เครดิตเหรียญให้ผู้ขาย + ลงรายการธุรกรรม (ต้องถูกเรียกใน TRANSACTION) */
async function creditSellerCoins(client, { sellerId, amountSatang }) {
  const rate = await getCoinRate(client);
  const coinsToCredit = Math.floor(Number(amountSatang) / rate);

  // ถ้าโพสต์ราคาถูกมากจนหารแล้วได้ 0 เหรียญ ให้ข้าม (ไม่ลบล้างเงินสดที่เก็บไว้)
  if (coinsToCredit <= 0) {
    // ลงรายการ Satang ไว้เฉย ๆ ก็ได้ เพื่อ audit
    await client.query(
      `INSERT INTO wallet_transactions
         (user_id, type, amount_satang, coins, rate_satang_per_coin, note, created_at)
       VALUES ($1, 'credit_purchase', $2, $3, $4, $5, now())`,
      [sellerId, Number(amountSatang), 0, rate, 'sale income (rounding to 0 coins)']
    );
    return;
  }

  // ล็อก/อ่านกระเป๋า
  const uw = await client.query(
    `SELECT coins FROM user_wallets WHERE user_id = $1 FOR UPDATE`,
    [sellerId]
  );

  if (uw.rowCount === 0) {
    await client.query(
      `INSERT INTO user_wallets (user_id, coins, updated_at)
       VALUES ($1, $2, now())`,
      [sellerId, coinsToCredit]
    );
  } else {
    await client.query(
      `UPDATE user_wallets
          SET coins = coins + $2,
              updated_at = now()
        WHERE user_id = $1`,
      [sellerId, coinsToCredit]
    );
  }

  await client.query(
    `INSERT INTO wallet_transactions
       (user_id, type, amount_satang, coins, rate_satang_per_coin, note, created_at)
     VALUES ($1, 'credit_purchase', $2, $3, $4, 'sale income', now())`,
    [sellerId, Number(amountSatang), coinsToCredit, rate]
  );
}

exports.createPurchase = async (req, res) => {
  try {
    const { postId, buyerId } = req.body || {};
    if (!postId || !buyerId) return res.status(400).json({ error: 'missing postId/buyerId' });

    const { rows: [post] } = await pool.query(
      `SELECT p.id, p.user_id AS seller_id, p.price_type, p.price_amount_satang, u.phone AS seller_phone
         FROM public.posts p
         LEFT JOIN public.users u ON u.id_user = p.user_id
        WHERE p.id=$1`, [postId]
    );
    if (!post) return res.status(404).json({ error: 'post_not_found' });
    if (post.price_type !== 'paid' || post.price_amount_satang <= 0) {
      return res.status(400).json({ error: 'post_is_free' });
    }

    const owned = await pool.query(
      `SELECT 1 FROM public.purchased_posts WHERE user_id=$1 AND post_id=$2 LIMIT 1`,
      [buyerId, postId]
    );
    if (owned.rowCount > 0) return res.json({ ok: true, already_owned: true });

    const amountBaht = post.price_amount_satang / 100.0;
    const mobileToUse = (post.seller_phone && String(post.seller_phone).replace(/\D/g, '')) || ADMIN_MOBILE;
    if (!mobileToUse) return res.status(400).json({ error: 'seller_no_phone' });

    // ใช้ PromptPay payload ของจริง
    const payload = generatePromptPayPayload({ target: mobileToUse, amount: amountBaht });

    // ทำเป็น SVG เพื่อแสดงในแอป
    const svg = await QRCode.toString(payload, { type: 'svg', errorCorrectionLevel: 'M' });
    const qrSvg = 'data:image/svg+xml;utf8,' + encodeURIComponent(svg);

    const expiresAt = new Date(Date.now() + TEN_MINUTES_MS);

    const { rows: [p] } = await pool.query(
      `INSERT INTO public.purchases
        (post_id, seller_id, buyer_id, amount_satang, status, expires_at, qr_payload, qr_svg, created_at, updated_at)
       VALUES ($1, $2, $3, $4, 'pending', $5, $6, $7, NOW(), NOW())
       RETURNING *`,
      [postId, post.seller_id, buyerId, post.price_amount_satang, expiresAt, payload, qrSvg]
    );

    res.json({ ok: true, purchase: p });
  } catch (e) {
    console.error('createPurchase error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

exports.getPurchase = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { rows: [p] } = await pool.query(`SELECT * FROM public.purchases WHERE id=$1`, [id]);
    if (!p) return res.status(404).json({ error: 'not_found' });

    const now = Date.now();
    const exp  = new Date(p.expires_at).getTime();
    const isExpired = now > exp && (p.status !== 'approved' && p.status !== 'rejected');

    return res.json({ ok: true, purchase: p, expired: isExpired });
  } catch (e) {
    console.error('getPurchase error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

exports.uploadSlip = async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!req.file) return res.status(400).json({ error: 'no_file' });

    const { rows: [p0] } = await pool.query(
      `SELECT * FROM public.purchases WHERE id=$1`, [id]
    );
    if (!p0) return res.status(404).json({ error: 'not_found' });

    // บันทึกไฟล์สลิป
    const filePath = `/uploads/slips/${req.file.filename}`;
    const fullPath = path.join(process.cwd(), 'uploads', 'slips', req.file.filename);

    await pool.query(
      `INSERT INTO public.payment_slips (purchase_id, file_path, uploaded_at)
       VALUES ($1,$2, NOW())`,
      [id, filePath]
    );

    let verificationResult = null;

    try {
      const amountBaht = p0.amount_satang / 100;
      verificationResult = await verifySlip(fullPath, amountBaht, SLIP_TOLERANCE_PERCENT);
      console.log(`[Slip Verification] Purchase ID: ${id}, Result:`, verificationResult);

      if (verificationResult.verified) {
        // ======= AUTO APPROVE (do in a TX) =======
        const client = await pool.connect();
        try {
          await client.query('BEGIN');

          const { rows: [approved] } = await client.query(
            `UPDATE public.purchases
                SET status='approved', updated_at=NOW(), auto_verified_at=NOW()
              WHERE id=$1
              RETURNING *`,
            [id]
          );

          // ให้สิทธิ์เข้าถึงโพสต์
          await client.query(
            `INSERT INTO public.purchased_posts (user_id, post_id, granted_at, purchase_id)
             VALUES ($1,$2,NOW(), $3)
             ON CONFLICT DO NOTHING`,
            [p0.buyer_id, p0.post_id, p0.id]
          );

          // ✅ เครดิตเหรียญให้ผู้ขาย
          await creditSellerCoins(client, { sellerId: p0.seller_id, amountSatang: p0.amount_satang });

          await client.query('COMMIT');

          // แจ้ง realtime (ไม่ต้องอยู่ใน TX)
          try {
            const io = req.app.get('io');
            if (io) {
              io.to(`user:${p0.buyer_id}`).emit('purchase_approved', {
                purchaseId: approved.id,
                postId: p0.post_id,
              });
            }
          } catch (err) {
            console.warn('Socket emit purchase_approved failed:', err.message);
          }

          return res.json({
            ok: true,
            purchase: approved,
            slip_path: filePath,
            auto_verified: true,
            verification: verificationResult,
          });
        } catch (txErr) {
          try { await client.query('ROLLBACK'); } catch (_) {}
          client.release();
          throw txErr;
        } finally {
          // ถ้าไม่ถูก throw ไปแล้ว ให้ release
          try { client.release(); } catch (_) {}
        }
      }
    } catch (verifyError) {
      console.warn(`[Slip Verification Failed] Purchase ID: ${id}:`, verifyError.message);
      verificationResult = { verified: false, error: verifyError.message };
    }

    // อ่านไม่ผ่าน → เก็บผลตรวจกับสลिप สถานะ purchase ยัง pending
    await pool.query(
      `UPDATE public.payment_slips
         SET verification_result = $2
       WHERE purchase_id = $1`,
      [id, verificationResult ? JSON.stringify(verificationResult) : null]
    );

    const { rows: [p] } = await pool.query(
      `SELECT * FROM public.purchases WHERE id=$1`, [id]
    );

    return res.json({
      ok: true,
      purchase: p,
      slip_path: filePath,
      auto_verified: false,
      verification: verificationResult,
      message: 'Slip uploaded. Pending manual verification.',
    });
  } catch (e) {
    console.error('uploadSlip error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

exports.listPendingSlips = async (_req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT p.*,
              bu.username AS buyer_name,
              su.username AS seller_name,
              (SELECT file_path
                 FROM public.payment_slips s
                WHERE s.purchase_id = p.id
                ORDER BY uploaded_at DESC
                LIMIT 1) AS last_slip
         FROM public.purchases p
         JOIN public.users bu ON bu.id_user = p.buyer_id
         JOIN public.users su ON su.id_user = p.seller_id
        WHERE p.status = 'pending'
        ORDER BY p.updated_at DESC`
    );
    res.json({ ok: true, items: rows });
  } catch (e) {
    console.error('listPendingSlips error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

exports.approvePurchase = async (req, res) => {
  const client = await pool.connect();
  try {
    const id = Number(req.params.id);
    const adminId = Number(req.body?.admin_id || 0);

    await client.query('BEGIN');

    const { rows: [p] } = await client.query(
      `SELECT * FROM public.purchases WHERE id=$1 FOR UPDATE`, [id]
    );
    if (!p) { 
      await client.query('ROLLBACK'); 
      return res.status(404).json({ error: 'not_found' }); 
    }

    if (p.status === 'approved') {
      await client.query('ROLLBACK');
      return res.json({ ok: true, message: 'already_approved' });
    }

    // ให้สิทธิ์เข้าถึงโพสต์
    await client.query(
      `INSERT INTO public.purchased_posts (user_id, post_id, granted_at, purchase_id)
       VALUES ($1,$2,NOW(), $3)
       ON CONFLICT DO NOTHING`,
      [p.buyer_id, p.post_id, p.id]
    );

    // ✅ เครดิตเหรียญให้ผู้ขาย
    await creditSellerCoins(client, { sellerId: p.seller_id, amountSatang: p.amount_satang });

    const { rows: [p2] } = await client.query(
      `UPDATE public.purchases
          SET status='approved', updated_at=NOW(), 
              admin_id=$2, manually_approved_at=NOW()
        WHERE id=$1
        RETURNING *`,
      [id, adminId || null]
    );

    await client.query('COMMIT');
    res.json({ ok: true, purchase: p2, message: 'manually_approved' });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('approvePurchase error:', e);
    res.status(500).json({ error: 'internal_error' });
  } finally {
    client.release();
  }
};

exports.rejectPurchase = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { rows: [p] } = await pool.query(
      `UPDATE public.purchases
          SET status='rejected', updated_at=NOW()
        WHERE id=$1
        RETURNING *`,
      [id]
    );
    if (!p) return res.status(404).json({ error: 'not_found' });
    res.json({ ok: true, purchase: p });
  } catch (e) {
    console.error('rejectPurchase error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

exports.listPurchasedPosts = async (req, res) => {
  try {
    const userId = Number(req.params.userId);
    if (!userId) return res.status(400).json({ error: 'missing userId' });

    const sql = `
      SELECT
        p.id,
        p.user_id,
        p.text,
        p.subject,
        p.year_label,
        p.image_url,
        p.file_url,
        p.price_type,
        p.price_amount_satang,
        u.username,
        COALESCE(u.avatar_url, '') AS avatar_url,
        ARRAY_REMOVE(ARRAY_AGG(pi.image_path ORDER BY pi.id), NULL) AS images,
        pp.granted_at
      FROM public.purchased_posts pp
      JOIN public.posts p      ON p.id = pp.post_id
      JOIN public.users u      ON u.id_user = p.user_id
      LEFT JOIN public.post_images pi ON pi.post_id = p.id
      WHERE pp.user_id = $1
      GROUP BY p.id, u.username, u.avatar_url, pp.granted_at
      ORDER BY pp.granted_at DESC;
    `;
    const { rows } = await pool.query(sql, [userId]);
    return res.json(rows);
  } catch (e) {
    console.error('listPurchasedPosts error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
};
