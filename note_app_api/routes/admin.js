// routes/admin.js
const express = require("express");
const router = express.Router();
const pool = require("../models/db");
const dayjs = require("dayjs");

/* ------------ guard ------------- */
function requireAdmin(req, res, next) {
  if (req.session?.isAdmin) return next();
  return res.redirect("/admin/login");
}

/* ------------ auth pages ------------- */
router.get("/admin/login", (req, res) => {
  res.render("admin_login", { error: null });
});

router.post("/admin/login", (req, res) => {
  const { password } = req.body || {};
  if (password && password === process.env.ADMIN_PASSWORD) {
    req.session.isAdmin = true;
    return res.redirect("/admin");
  }
  return res.render("admin_login", { error: "Invalid password" });
});

router.post("/admin/logout", (req, res) => {
  req.session.destroy(() => res.redirect("/admin/login"));
});

/* ------------ dashboard ------------- */
router.get("/admin", requireAdmin, async (_req, res) => {
  const [{ rows: p1 }, { rows: p2 }] = await Promise.all([
    pool.query(`SELECT count(*) FROM purchases WHERE status='pending'`),
    pool.query(`SELECT count(*) FROM withdrawals WHERE status='pending'`), // ✅ ใช้ withdrawals
  ]);
  res.render("admin_home", {
    pendingPurchases: Number(p1[0].count || 0),
    pendingPayouts: Number(p2[0].count || 0),
  });
});

/* ============ PURCHASES ============ */
router.get("/admin/purchases", requireAdmin, async (req, res) => {
  const status = req.query.status || "pending";
  const q = await pool.query(
    `SELECT pu.id, pu.post_id, pu.buyer_id, pu.seller_id, pu.amount_satang,
            pu.status, pu.expires_at, pu.created_at,
            p.text AS post_text,
            ub.username AS buyer_name,
            us.username AS seller_name,
            ps.file_path AS slip_path
     FROM purchases pu
     JOIN posts p    ON p.id = pu.post_id
     JOIN users ub   ON ub.id_user = pu.buyer_id   -- ✅ ตรง schema
     JOIN users us   ON us.id_user = pu.seller_id  -- ✅ ตรง schema
     LEFT JOIN LATERAL (
       SELECT file_path FROM payment_slips s
       WHERE s.purchase_id = pu.id
       ORDER BY id DESC LIMIT 1
     ) ps ON true
     WHERE pu.status = $1
     ORDER BY pu.created_at DESC`,
    [status]
  );
  res.render("admin_purchases", { rows: q.rows, status, dayjs });
});

/* อนุมัติการซื้อ */
router.post("/admin/purchases/:id/approve", requireAdmin, async (req, res) => {
  const id = Number(req.params.id);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const cur = await client.query(
      `SELECT id, post_id, buyer_id, seller_id, amount_satang, status
         FROM purchases WHERE id = $1 FOR UPDATE`,
      [id]
    );
    if (cur.rowCount === 0) throw new Error("purchase_not_found");
    const o = cur.rows[0];
    if (o.status !== "pending") throw new Error("invalid_status");

    // ให้สิทธิ์ผู้ซื้อ
    await client.query(
      `INSERT INTO purchased_posts (post_id, user_id, purchase_id)
       VALUES ($1, $2, $3)
       ON CONFLICT DO NOTHING`,
      [o.post_id, o.buyer_id, o.id]
    );

    // เครดิตเหรียญแก่ผู้ขาย (บันทึกเป็นธุรกรรม พร้อม coins/rate)
    const rateRow = await client.query(
      `SELECT COALESCE(coin_rate_satang_per_coin,100) AS rate
       FROM admin_settings WHERE id=1`
    );
    const rate = Number(rateRow.rows[0]?.rate || 100);
    const coins = Math.floor(Number(o.amount_satang) / rate);

    await client.query(
      `INSERT INTO user_wallets (user_id, coins, updated_at)
       VALUES ($1, $2, now())
       ON CONFLICT (user_id) DO UPDATE
         SET coins = user_wallets.coins + EXCLUDED.coins,
             updated_at = now()`,
      [o.seller_id, coins]
    );

    await client.query(
      `INSERT INTO wallet_transactions
        (user_id, type, amount_satang, coins, rate_satang_per_coin, related_purchase_id, note, created_at)
       VALUES ($1, 'credit_purchase', $2, $3, $4, $5, 'sale income', now())`,
      [o.seller_id, o.amount_satang, coins, rate, o.id]
    );

    await client.query(
      `UPDATE purchases SET status='approved' WHERE id=$1`,
      [o.id]
    );

    await client.query("COMMIT");
    res.redirect("/admin/purchases?status=pending");
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("approve purchase error:", e);
    res.status(500).send(String(e));
  } finally {
    client.release();
  }
});

/* ปฏิเสธการซื้อ */
router.post("/admin/purchases/:id/reject", requireAdmin, async (req, res) => {
  const id = Number(req.params.id);
  try {
    await pool.query(
      `UPDATE purchases SET status='rejected' WHERE id=$1 AND status='pending'`,
      [id]
    );
    res.redirect("/admin/purchases?status=pending");
  } catch (e) {
    console.error("reject purchase error:", e);
    res.status(500).send("internal_error");
  }
});

/* ============ PAYOUTS (WITHDRAWALS) ============ */

/** รายการถอนตามสถานะ (ค่าเริ่มต้น: pending) */
router.get("/admin/payouts", requireAdmin, async (req, res) => {
  const status = req.query.status || "pending";

  const q = await pool.query(
    `SELECT w.id, w.user_id, w.coins, w.rate_satang_per_coin, w.amount_satang,
            w.bank_qr_file, w.status, w.created_at,
            u.username
     FROM withdrawals w
     JOIN users u ON u.id_user = w.user_id
     WHERE w.status = $1
     ORDER BY w.created_at DESC`,
    [status]
  );

  // enrich สำหรับแสดงผล
  const rows = q.rows.map(r => ({
    ...r,
    gross_baht: Number(r.amount_satang || 0) / 100,
    net_baht:   Number(r.amount_satang || 0) / 100, // ถ้าไม่มีค่าธรรมเนียม เพิ่ม logic หักได้ที่นี่
    bank_qr_file: r.bank_qr_file || null,
  }));

  res.render("admin_payouts", { rows, status, dayjs });
});

/** กด Mark paid -> ตัดเหรียญจริง, ปิดสถานะเป็น paid */
router.post("/admin/payouts/:id/mark-paid", requireAdmin, async (req, res) => {
  const id = Number(req.params.id);
  const adminId = Number(req.session?.admin_user_id || 0) || null;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const cur = await client.query(
      `SELECT id, user_id, coins, amount_satang, status
       FROM withdrawals
       WHERE id=$1 FOR UPDATE`,
      [id]
    );
    if (cur.rowCount === 0) throw new Error("withdrawal_not_found");
    const w = cur.rows[0];
    if (w.status !== "pending") throw new Error("invalid_status");

    // บันทึกธุรกรรมจ่ายออก (amount/coins เป็นค่าลบ)
    await client.query(
      `INSERT INTO wallet_transactions
        (user_id, type, amount_satang, coins, note, created_at)
       VALUES ($1, 'debit_payout', $2, $3, 'payout paid', now())`,
      [w.user_id, Number(w.amount_satang) * -1, Number(w.coins) * -1]
    );
    // หมายเหตุ: ไม่ยัด related_payout_id เพราะคอลัมน์เป็น uuid แต่ withdrawals.id เป็น bigint

    await client.query(
      `UPDATE withdrawals
         SET status='paid', paid_at=now(), admin_id=$2
       WHERE id=$1`,
      [w.id, adminId]
    );

    await client.query("COMMIT");
    res.redirect("/admin/payouts?status=pending");
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("mark paid error:", e);
    res.status(500).send(String(e));
  } finally {
    client.release();
  }
});

module.exports = router;
