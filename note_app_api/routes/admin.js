// routes/admin.js
const express = require("express");
const router = express.Router();
const pool = require("../models/db");
const dayjs = require("dayjs");

function requireAdmin(req, res, next) {
  if (req.session?.isAdmin) return next();
  return res.redirect("/admin/login");
}

// --- Login page ---
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

// --- Dashboard ---
router.get("/admin", requireAdmin, async (req, res) => {
  // นับงานค้าง
  const [{ rows: p1 }, { rows: p2 }] = await Promise.all([
    pool.query(`SELECT count(*) FROM purchases WHERE status='pending'`),
    pool.query(`SELECT count(*) FROM payout_requests WHERE status='pending'`),
  ]);
  res.render("admin_home", {
    pendingPurchases: Number(p1[0].count || 0),
    pendingPayouts: Number(p2[0].count || 0),
  });
});

// ============== PURCHASES ==============
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
     JOIN posts p   ON p.id = pu.post_id
     JOIN users ub  ON ub.id_user = pu.buyer_id
     JOIN users us  ON us.id_user = pu.seller_id
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

// อนุมัติการโอน -> ให้สิทธิ์โพสต์ + เติมเหรียญให้ผู้ขาย
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
      `INSERT INTO purchased_posts (post_id, buyer_id)
        VALUES ($1, $2)
        ON CONFLICT (post_id, buyer_id) DO NOTHING`,
      [o.post_id, o.buyer_id]
    );

    // เติมเหรียญให้ผู้ขาย (บวกเท่ากับยอด)
    await client.query(
      `INSERT INTO wallet_transactions
         (user_id, type, amount_satang, related_purchase_id, note)
       VALUES ($1, 'credit_purchase', $2, $3, 'sale income')`,
      [o.seller_id, o.amount_satang, o.id]
    );

    await client.query(
      `INSERT INTO post_access (post_id, user_id, granted_at)
        VALUES ($1, $2, now())
        ON CONFLICT DO NOTHING`,
      [o.post_id, o.buyer_id]
    );

    // ปิดออเดอร์
    await client.query(`UPDATE purchases SET status='paid' WHERE id=$1`, [
      o.id,
    ]);

    await client.query("COMMIT");
    res.redirect("/admin/purchases?status=pending");
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("approve purchase error:", e); // ดูที่ console จะเห็น SQL error จริง
    // ชั่วคราวเพื่อดีบัก: ส่งข้อความจริงให้เห็น
    res.status(500).send(String(e));
  } finally {
    client.release();
  }
});

// ปฏิเสธ
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

// ============== PAYOUTS (ถอนเงิน) ==============
router.get("/admin/payouts", requireAdmin, async (req, res) => {
  const status = req.query.status || "pending";
  const q = await pool.query(
    `SELECT pr.id, pr.user_id, pr.amount_satang, pr.amount_satang_net,
            pr.status, pr.promptpay_mobile, pr.created_at,
            u.username
     FROM payout_requests pr
     JOIN users u ON u.id_user = pr.user_id
     WHERE pr.status = $1
     ORDER BY pr.created_at DESC`,
    [status]
  );
  res.render("admin_payouts", { rows: q.rows, status, dayjs });
});

// ทำเครื่องหมายว่า "โอนแล้ว" -> ตัดเหรียญออก (debit)
router.post("/admin/payouts/:id/mark-paid", requireAdmin, async (req, res) => {
  const id = Number(req.params.id);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const cur = await client.query(
      `SELECT id, user_id, amount_satang, amount_satang_net, status
       FROM payout_requests WHERE id=$1 FOR UPDATE`,
      [id]
    );
    if (cur.rowCount === 0) throw new Error("payout_not_found");
    const o = cur.rows[0];
    if (o.status !== "pending") throw new Error("invalid_status");

    // ตัดเหรียญจริงเท่ากับยอดสุทธิ (net)
    await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount_satang, related_payout_id, note)
       VALUES ($1, 'debit_payout', $2 * -1, $3, 'payout to user')`,
      [o.user_id, o.amount_satang_net, o.id]
    );

    await client.query(
      `UPDATE payout_requests SET status='paid', paid_at=now() WHERE id=$1`,
      [o.id]
    );

    await client.query("COMMIT");
    res.redirect("/admin/payouts?status=pending");
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("mark paid error:", e);
    res.status(500).send("internal_error");
  } finally {
    client.release();
  }
});

module.exports = router;
