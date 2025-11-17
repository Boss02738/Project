// controllers/purchaseController.js
const pool = require('../models/db');
const QRCode = require('qrcode');
const path = require('path');
const { generatePromptPayPayload } = require('../utils/promptpay');
const { verifyWithSlipOK } = require('../utils/slipok'); // ✅ ใช้ SlipOK จริง

const TEN_MINUTES_MS = 10 * 60 * 1000;
const ADMIN_MOBILE = (process.env.ADMIN_PROMPTPAY_PHONE || '').replace(/\D/g, '');

// ===== 1) สร้างคำสั่งซื้อ + สร้าง QR พร้อมเพย์ของจริง =====
exports.createPurchase = async (req, res) => {
  try {
    const { postId, buyerId } = req.body || {};
    if (!postId || !buyerId) {
      return res.status(400).json({ error: 'missing postId/buyerId' });
    }

    const { rows: [post] } = await pool.query(
      `SELECT p.id,
              p.user_id AS seller_id,
              p.price_type,
              p.price_amount_satang,
              u.phone AS seller_phone
         FROM public.posts p
         LEFT JOIN public.users u ON u.id_user = p.user_id
        WHERE p.id = $1`,
      [postId]
    );

    if (!post) {
      return res.status(404).json({ error: 'post_not_found' });
    }
    if (post.price_type !== 'paid' || post.price_amount_satang <= 0) {
      return res.status(400).json({ error: 'post_is_free' });
    }

    // เคยซื้อแล้วหรือยัง
    const owned = await pool.query(
      `SELECT 1
         FROM public.purchased_posts
        WHERE user_id = $1 AND post_id = $2
        LIMIT 1`,
      [buyerId, postId]
    );
    if (owned.rowCount > 0) {
      return res.json({ ok: true, already_owned: true });
    }

    const amountBaht = post.price_amount_satang / 100.0;
const mobileToUse = ADMIN_MOBILE;
if (!mobileToUse) {
  return res.status(400).json({ error: 'seller_no_phone' });
}

    // ✅ QR พร้อมเพย์จริง
    const payload = generatePromptPayPayload({
      target: mobileToUse,
      amount: amountBaht,
    });

    const svg = await QRCode.toString(payload, {
      type: 'svg',
      errorCorrectionLevel: 'M',
    });
    const qrSvg = 'data:image/svg+xml;utf8,' + encodeURIComponent(svg);

    const expiresAt = new Date(Date.now() + TEN_MINUTES_MS);

    const { rows: [p] } = await pool.query(
      `INSERT INTO public.purchases
        (post_id, seller_id, buyer_id, amount_satang,
         status, expires_at, qr_payload, qr_svg,
         created_at, updated_at)
       VALUES ($1,$2,$3,$4,'pending',$5,$6,$7,NOW(),NOW())
       RETURNING *`,
      [
        postId,
        post.seller_id,
        buyerId,
        post.price_amount_satang,
        expiresAt,
        payload,
        qrSvg,
      ]
    );

    return res.json({ ok: true, purchase: p });
  } catch (e) {
    console.error('createPurchase error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
};

// ===== 2) ดึงสถานะคำสั่งซื้อ =====
exports.getPurchase = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { rows: [p] } = await pool.query(
      `SELECT * FROM public.purchases WHERE id = $1`,
      [id]
    );
    if (!p) {
      return res.status(404).json({ error: 'not_found' });
    }

    const now = Date.now();
    const exp = new Date(p.expires_at).getTime();
    const expired =
      now > exp && !['approved', 'rejected'].includes(p.status);

    return res.json({ ok: true, purchase: p, expired });
  } catch (e) {
    console.error('getPurchase error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
};

// ===== 3) อัปโหลดสลิป + ตรวจด้วย SlipOK + อนุมัติ/เครดิตเหรียญอัตโนมัติ =====
exports.uploadSlip = async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!req.file) {
      return res.status(400).json({ error: 'no_file' });
    }

    const { rows: [p0] } = await pool.query(
      `SELECT * FROM public.purchases WHERE id = $1`,
      [id]
    );
    if (!p0) {
      return res.status(404).json({ error: 'not_found' });
    }

    const filePath = `/uploads/slips/${req.file.filename}`;
    const fullPath = path.join(
      process.cwd(),
      'uploads',
      'slips',
      req.file.filename
    );

    // 1) บันทึกสลิปลง DB
    await pool.query(
      `INSERT INTO public.payment_slips (purchase_id, file_path, uploaded_at)
       VALUES ($1,$2,NOW())`,
      [id, filePath]
    );

    // 2) ตรวจสลิปจริงด้วย SlipOK
    const expectBaht = Number(p0.amount_satang) / 100;
    const slip = await verifyWithSlipOK(fullPath, expectBaht);

    // === ผ่าน: อนุมัติ + ให้สิทธิ์ + เติมเหรียญผู้ขาย (ทั้งหมดใน transaction) ===
    if (slip.verified) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // อนุมัติคำสั่งซื้อ
        const { rows: [approved] } = await client.query(
          `UPDATE public.purchases
              SET status = 'approved',
                  updated_at = NOW(),
                  auto_verified_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [id]
        );

        // ให้สิทธิ์เข้าถึงโพสต์
        await client.query(
          `INSERT INTO public.purchased_posts
             (user_id, post_id, granted_at, purchase_id)
           VALUES ($1,$2,NOW(),$3)
           ON CONFLICT DO NOTHING`,
          [p0.buyer_id, p0.post_id, p0.id]
        );

        // เติมเหรียญให้ผู้ขาย
        const rateRow = await client.query(
          `SELECT COALESCE(coin_rate_satang_per_coin, 100) AS rate
             FROM admin_settings
            WHERE id = 1`
        );
        const rate = Number(rateRow.rows[0]?.rate || 100);
        const coins = Math.floor(Number(p0.amount_satang) / rate);

        await client.query(
          `INSERT INTO user_wallets (user_id, coins, updated_at)
           VALUES ($1,$2,now())
           ON CONFLICT (user_id) DO UPDATE
             SET coins = user_wallets.coins + EXCLUDED.coins,
                 updated_at = now()`,
          [p0.seller_id, coins]
        );

        await client.query(
          `INSERT INTO wallet_transactions
             (user_id, type, amount_satang, coins, rate_satang_per_coin,
              related_purchase_id, note, created_at)
           VALUES ($1,'credit_purchase',$2,$3,$4,$5,'sale income',now())`,
          [p0.seller_id, p0.amount_satang, coins, rate, p0.id]
        );

        await client.query('COMMIT');

        // แจ้งผู้ซื้อ realtime (ไม่ critical)
        try {
          const io = req.app.get('io');
          if (io) {
            io.to(`user:${p0.buyer_id}`).emit('purchase_approved', {
              purchaseId: approved.id,
              postId: p0.post_id,
            });
          }
        } catch (err) {
          console.warn(
            'Socket emit purchase_approved failed:',
            err.message
          );
        }

        return res.json({
          ok: true,
          purchase: approved,
          slip_path: filePath,
          auto_verified: true,
          verification: { provider: 'slipok', amount: slip.amount },
        });
      } catch (e) {
        await client.query('ROLLBACK');
        console.error('uploadSlip tx error:', e);
        return res.status(500).json({ error: 'internal_error' });
      } finally {
        client.release();
      }
    }

    // === ไม่ผ่าน: เก็บผลตรวจไว้กับสลิป ปล่อยให้ pending ===
    await pool.query(
      `UPDATE public.payment_slips
          SET verification_result = $2
        WHERE purchase_id = $1`,
      [id, JSON.stringify({ provider: 'slipok', ...slip })]
    );

    const { rows: [p] } = await pool.query(
      `SELECT * FROM public.purchases WHERE id = $1`,
      [id]
    );

    return res.json({
      ok: true,
      purchase: p,
      slip_path: filePath,
      auto_verified: false,
      verification: {
        provider: 'slipok',
        code: slip.code,
        message: slip.message,
      },
      message: 'Slip uploaded. Pending manual verification.',
    });
  } catch (e) {
    console.error('uploadSlip error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
};

// ===== 4) รายการโพสต์ที่ user ซื้อแล้ว (ใช้บน PurchasedPostsScreen) =====
exports.listPurchasedPosts = async (req, res) => {
  try {
    const userId = Number(req.params.userId);
    if (!userId) {
      return res.status(400).json({ error: 'missing userId' });
    }

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

// ===== 5) อนุมัติมือผ่าน /api/purchases/:id/approve (ถ้าใช้จาก mobile admin) =====
exports.approvePurchase = async (req, res) => {
  // ถ้ายังไม่ได้ใช้ endpoint นี้จริง ๆ จะทำสั้น ๆ ไว้ก่อน
  // (เพราะฝั่ง web admin มี logic เต็มอยู่ใน routes/admin.js แล้ว)
  try {
    const id = Number(req.params.id);
    if (!id) return res.status(400).json({ error: 'invalid_id' });

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const { rows: [p] } = await client.query(
        `SELECT * FROM public.purchases WHERE id=$1 FOR UPDATE`,
        [id]
      );
      if (!p) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'not_found' });
      }
      if (p.status === 'approved') {
        await client.query('ROLLBACK');
        return res.json({ ok: true, message: 'already_approved' });
      }

      await client.query(
        `INSERT INTO public.purchased_posts (user_id, post_id, granted_at, purchase_id)
         VALUES ($1,$2,NOW(),$3)
         ON CONFLICT DO NOTHING`,
        [p.buyer_id, p.post_id, p.id]
      );

      const { rows: [p2] } = await client.query(
        `UPDATE public.purchases
            SET status='approved',
                updated_at=NOW(),
                manually_approved_at=NOW()
          WHERE id=$1
          RETURNING *`,
        [id]
      );

      await client.query('COMMIT');
      return res.json({ ok: true, purchase: p2, message: 'manually_approved' });
    } catch (e) {
      await client.query('ROLLBACK');
      console.error('approvePurchase error:', e);
      return res.status(500).json({ error: 'internal_error' });
    } finally {
      client.release();
    }
  } catch (e) {
    console.error('approvePurchase outer error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
};

// ===== 6) ปฏิเสธคำสั่งซื้อผ่าน /api/purchases/:id/reject =====
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
    if (!p) {
      return res.status(404).json({ error: 'not_found' });
    }
    return res.json({ ok: true, purchase: p });
  } catch (e) {
    console.error('rejectPurchase error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
};
