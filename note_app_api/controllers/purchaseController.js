// controllers/purchaseController.js
const pool = require('../models/db');
const QRCode = require('qrcode');

/** ====== CONFIG ====== */
const TEN_MINUTES_MS = 10 * 60 * 1000;
// เบอร์ PromptPay ของแอดมิน (รับเงินเข้ากลาง แล้วค่อยเคลียร์ให้ผู้ขายภายหลัง)
const ADMIN_MOBILE = (process.env.ADMIN_MOBILE || '').replace(/\D/g, '');

/** ====== Helper: สร้าง PromptPay EMV payload แบบเดโม่ (พอทดสอบได้) ======
 *  ถ้าต้องการความถูกต้อง 100% ตาม EMVCo + CRC16-CCITT แนะนำใช้ไลบรารีเฉพาะ
 *  หรือแพ็กเกจ promptpay-qr ใน production
 */
function generatePromptPayPayload({ mobile, amountBaht }) {
  const m = String(mobile || '').replace(/\D/g, '');
  if (!m) throw new Error('missing admin mobile');
  const amt = Number(amountBaht || 0).toFixed(2);

  // Payload นี้เป็นแบบลดรูป เพื่อการทดสอบพื้นฐานกับแอปธนาคารส่วนใหญ่
  // หมายเหตุ: ไม่ใส่ CRC จริง (ใส่ FFFF ไว้แทน)
  const len = m.length.toString().padStart(2, '0');
  const payload =
    `000201010211` +
    `2937` + `0016A0000006770101110213` + len + m +
    `5303764` +                // THB
    `540${amt.length}${amt}` + // Amount
    `5802TH` +
    `5913NoteCoLab Post` +
    `6009Bangkok` +
    `6304FFFF`;
  return payload;
}

/** ====== สร้างคำสั่งซื้อ: POST /api/purchases {postId, buyerId} ====== */
exports.createPurchase = async (req, res) => {
  try {
    const { postId, buyerId } = req.body || {};
    if (!postId || !buyerId) return res.status(400).json({ error: 'missing postId/buyerId' });
    if (!ADMIN_MOBILE) return res.status(500).json({ error: 'missing_admin_mobile' });

    // ดึงข้อมูลโพสต์และราคา
    const { rows: [post] } = await pool.query(
      `SELECT id, user_id AS seller_id, price_type, price_amount_satang
         FROM public.posts
        WHERE id=$1`, [postId]
    );
    if (!post) return res.status(404).json({ error: 'post_not_found' });
    if (post.price_type !== 'paid' || post.price_amount_satang <= 0) {
      return res.status(400).json({ error: 'post_is_free' });
    }

    // ถ้าเคยได้สิทธิ์แล้ว ไม่ต้องซื้อซ้ำ
    const owned = await pool.query(
      `SELECT 1 FROM public.purchased_posts WHERE buyer_id=$1 AND post_id=$2 LIMIT 1`,
      [buyerId, postId]
    );
    if (owned.rowCount > 0) {
      return res.json({ ok: true, already_owned: true });
    }

    // สร้าง QR ให้จ่ายเข้า "เบอร์แอดมิน" (รับเงินกลาง)
    const amountBaht = post.price_amount_satang / 100.0;
    const payload = generatePromptPayPayload({ mobile: ADMIN_MOBILE, amountBaht });

    // ทำเป็น SVG (คมชัดและเบากว่า PNG DataURL)
    const qrSvg = await QRCode.toString(payload, { type: 'svg', errorCorrectionLevel: 'M' });

    const expiresAt = new Date(Date.now() + TEN_MINUTES_MS);

    const { rows: [p] } = await pool.query(
      `INSERT INTO public.purchases
        (post_id, seller_id, buyer_id, amount_satang, status, expires_at, qr_payload, qr_svg, created_at, updated_at)
       VALUES ($1,$2,$3,$4,'qr_generated',$5,$6,$7, NOW(), NOW())
       RETURNING *`,
      [postId, post.seller_id, buyerId, post.price_amount_satang, expiresAt, payload, qrSvg]
    );

    res.json({
      ok: true,
      purchase: {
        id: p.id,
        post_id: p.post_id,
        seller_id: p.seller_id,
        buyer_id: p.buyer_id,
        status: p.status,
        amount_satang: p.amount_satang,
        expires_at: p.expires_at,
        qr_payload: p.qr_payload,
        qr_svg: p.qr_svg,
      }
    });
  } catch (e) {
    console.error('createPurchase error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

/** ====== ดูคำสั่งซื้อ: GET /api/purchases/:id ====== */
exports.getPurchase = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { rows: [p] } = await pool.query(`SELECT * FROM public.purchases WHERE id=$1`, [id]);
    if (!p) return res.status(404).json({ error: 'not_found' });

    // ถ้ายังไม่ approved และหมดอายุแล้ว → mark expired
    const now = Date.now();
    const exp = new Date(p.expires_at).getTime();
    if (p.status !== 'approved' && p.status !== 'rejected' && now > exp) {
      const { rows: [expd] } = await pool.query(
        `UPDATE public.purchases
            SET status='expired', updated_at=NOW()
          WHERE id=$1
          RETURNING *`,
        [id]
      );
      return res.json({ ok: true, purchase: expd, expired: true });
    }

    res.json({ ok: true, purchase: p });
  } catch (e) {
    console.error('getPurchase error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

/** ====== อัปโหลดสลิป: POST /api/purchases/:id/slip (field: slip) ====== */
exports.uploadSlip = async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!req.file) return res.status(400).json({ error: 'no_file' });

    // ตรวจว่ามี purchase จริง
    const { rows: [p0] } = await pool.query(`SELECT * FROM public.purchases WHERE id=$1`, [id]);
    if (!p0) return res.status(404).json({ error: 'not_found' });

    // บันทึกไฟล์
    const filePath = `/uploads/slips/${req.file.filename}`;
    await pool.query(
      `INSERT INTO public.payment_slips (purchase_id, file_path, uploaded_at)
       VALUES ($1,$2, NOW())`,
      [id, filePath]
    );

    // อัปเดตสถานะเป็น slip_uploaded
    const { rows: [p] } = await pool.query(
      `UPDATE public.purchases
          SET status='slip_uploaded', updated_at=NOW()
        WHERE id=$1
        RETURNING *`,
      [id]
    );

    res.json({ ok: true, purchase: p, slip_path: filePath });
  } catch (e) {
    console.error('uploadSlip error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

/** ====== (ADMIN) ดึงรายการรอตรวจสลิป: GET /api/purchases/admin/pending ====== */
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
        WHERE p.status IN ('slip_uploaded','qr_generated','pending')
        ORDER BY p.updated_at DESC`
    );
    res.json({ ok: true, items: rows });
  } catch (e) {
    console.error('listPendingSlips error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

/** ====== (ADMIN) อนุมัติ: POST /api/purchases/:id/approve ====== */
exports.approvePurchase = async (req, res) => {
  const client = await pool.connect();
  try {
    const id = Number(req.params.id);
    await client.query('BEGIN');

    const { rows: [p] } = await client.query(
      `SELECT * FROM public.purchases WHERE id=$1 FOR UPDATE`, [id]
    );
    if (!p) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'not_found' }); }

    // ให้สิทธิ์ผู้ซื้อ
    await client.query(
      `INSERT INTO public.purchased_posts (buyer_id, post_id)
       VALUES ($1,$2) ON CONFLICT (buyer_id, post_id) DO NOTHING`,
      [p.buyer_id, p.post_id]
    );

    const { rows: [p2] } = await client.query(
      `UPDATE public.purchases
          SET status='approved', updated_at=NOW()
        WHERE id=$1
        RETURNING *`,
      [id]
    );

    await client.query('COMMIT');
    res.json({ ok: true, purchase: p2 });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('approvePurchase error:', e);
    res.status(500).json({ error: 'internal_error' });
  } finally {
    client.release();
  }
};

/** ====== (ADMIN) ปฏิเสธ: POST /api/purchases/:id/reject ====== */
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
        p.user_id,                              -- เจ้าของโพสต์
        p.text,
        p.subject,
        p.year_label,
        p.image_url,
        p.file_url,
        p.price_type,
        p.price_amount_satang,

        -- ข้อมูลผู้โพสต์ (JOIN users)
        u.username,
        COALESCE(u.avatar_url, '') AS avatar_url,

        -- รวมรูปหลายใบถ้ามีตาราง post_images
        ARRAY_REMOVE(ARRAY_AGG(pi.image_path ORDER BY pi.id), NULL) AS images,

        -- เวลาที่ได้รับสิทธิ์
        pp.created_at,
        pp.granted_at
      FROM public.purchased_posts pp
      JOIN public.posts p      ON p.id = pp.post_id
      JOIN public.users u      ON u.id_user = p.user_id
      LEFT JOIN public.post_images pi ON pi.post_id = p.id
      WHERE pp.user_id = $1              -- ถ้าสคีมาของคุณใช้ buyer_id ให้เปลี่ยนเป็น pp.buyer_id
      GROUP BY p.id, u.username, u.avatar_url, pp.created_at, pp.granted_at
      ORDER BY pp.id DESC;
    `;

    const { rows } = await pool.query(sql, [userId]);
    return res.json(rows);
  } catch (e) {
    console.error('listPurchasedPosts error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
};