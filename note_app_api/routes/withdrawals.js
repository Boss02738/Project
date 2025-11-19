// // routes/withdrawals.js
// const express = require('express');
// const path   = require('path');
// const fs     = require('fs');
// const multer = require('multer');
// const pool   = require('../models/db');

// // 🔔 สำหรับสร้าง notification
// const notificationCtrl = require('../controllers/notificationController');

// const router = express.Router();

// // admin หลัก (ไว้รับ noti เวลา user ขอถอน)
// // สามารถเปลี่ยนเป็น env ได้: ADMIN_USER_ID=2
// const ADMIN_USER_ID = Number(process.env.ADMIN_USER_ID || 1);

// const dir = path.join(process.cwd(), 'uploads', 'withdraw_qr');
// fs.mkdirSync(dir, { recursive: true });

// const upload = multer({ dest: path.join(process.cwd(), 'uploads', 'slips') });

// async function getCoinRate(client) {
//   const r = await client.query(
//     `SELECT COALESCE(coin_rate_satang_per_coin, 100) AS rate
//      FROM admin_settings WHERE id = 1`
//   );
//   return Number(r.rows[0]?.rate || 100);
// }

// // ============ USER: สร้างคำขอถอน ============
// router.post('/api/withdrawals', upload.single('qr'), async (req, res) => {
//   const userId = Number(req.body?.user_id || 0);
//   const coins  = Number(req.body?.coins   || 0);

//   if (!userId || !Number.isFinite(coins) || coins <= 0) {
//     return res.status(400).json({ error: 'invalid_params' });
//   }
//   if (!req.file) {
//     return res.status(400).json({ error: 'missing_qr_file' });
//   }

//   const client = await pool.connect();
//   try {
//     await client.query('BEGIN');

//     const uw = await client.query(
//       `SELECT coins FROM user_wallets WHERE user_id = $1 FOR UPDATE`,
//       [userId]
//     );
//     const current = Number(uw.rows[0]?.coins || 0);
//     if (current < coins) {
//       throw new Error('insufficient_coins');
//     }

//     const rate         = await getCoinRate(client);
//     const amountSatang = coins * rate;
//     const rel          = '/' + path
//       .relative(process.cwd(), req.file.path)
//       .replace(/\\/g, '/');

//     await client.query(
//       `UPDATE user_wallets
//          SET coins = coins - $2, updated_at = now()
//        WHERE user_id = $1`,
//       [userId, coins]
//     );

//     const tx = await client.query(
//       `INSERT INTO wallet_transactions
//         (user_id, type, amount_satang, coins, rate_satang_per_coin, note, created_at)
//        VALUES ($1, 'debit_withdrawal', $2, $3, $4, 'withdraw request', now())
//        RETURNING id`,
//       [userId, amountSatang, coins, rate]
//     );

//     const ins = await client.query(
//       `INSERT INTO withdrawals
//         (user_id, coins, rate_satang_per_coin, amount_satang, bank_qr_file, status, created_at)
//        VALUES ($1, $2, $3, $4, $5, 'pending', now())
//        RETURNING id, user_id, coins, rate_satang_per_coin, amount_satang, bank_qr_file, status, created_at`,
//       [userId, coins, rate, amountSatang, rel]
//     );

//     await client.query('COMMIT');

//     const withdrawal = ins.rows[0];

//     // 🔔 แจ้งเตือน ADMIN ว่ามีคำขอถอนใหม่
//     try {
//       await notificationCtrl.createAndEmit(req.app, {
//         targetUserId: ADMIN_USER_ID,         // แอดมินที่จะเห็น noti
//         actorId     : userId,                // คนกดถอน
//         action      : 'withdraw_request',    // action key
//         message     : `มีคำขอถอน ${coins} เหรียญจากผู้ใช้ #${userId}`,
//         postId      : null,
//       });
//     } catch (e) {
//       console.warn('notify admin withdraw_request failed:', e);
//     }

//     return res.status(201).json({ withdrawal });
//   } catch (e) {
//     await client.query('ROLLBACK');
//     console.error('create withdrawal error:', e);
//     if (String(e.message) === 'insufficient_coins') {
//       return res.status(400).json({ error: 'insufficient_coins' });
//     }
//     return res.status(500).json({ error: 'internal_error' });
//   } finally {
//     client.release();
//   }
// });

// // ============ USER: ประวัติถอนของฉัน ============
// router.get('/api/withdrawals/my', async (req, res) => {
//   const userId = Number(req.query.user_id || 0);
//   if (!userId) return res.status(400).json({ error: 'invalid_user' });

//   try {
//     const r = await pool.query(
//       `SELECT id, user_id, coins, rate_satang_per_coin, amount_satang,
//               bank_qr_file, status, admin_note, created_at, paid_at, rejected_at
//        FROM withdrawals
//        WHERE user_id = $1
//        ORDER BY created_at DESC`,
//       [userId]
//     );
//     return res.json({ items: r.rows });
//   } catch (e) {
//     console.error('get my withdrawals error:', e);
//     return res.status(500).json({ error: 'internal_error' });
//   }
// });

// // ============ ADMIN: ดูคิว pending ============
// router.get('/api/admin/withdrawals/pending', async (_req, res) => {
//   try {
//     const r = await pool.query(
//       `SELECT id, user_id, coins, rate_satang_per_coin, amount_satang,
//               bank_qr_file, status, created_at
//        FROM withdrawals
//        WHERE status = 'pending'
//        ORDER BY created_at DESC`
//     );
//     return res.json({ items: r.rows });
//   } catch (e) {
//     console.error('admin list withdrawals error:', e);
//     return res.status(500).json({ error: 'internal_error' });
//   }
// });

// // ============ ADMIN: อนุมัติถอน ============
// router.post('/api/admin/withdrawals/:id/approve', async (req, res) => {
//   const id = Number(req.params.id || 0);
//   const adminId = Number(req.body?.admin_id || 0);
//   const note = String(req.body?.note || 'withdrawal paid');

//   if (!id) return res.status(400).json({ error: 'invalid_id' });

//   const client = await pool.connect();
//   try {
//     await client.query('BEGIN');

//     const wq = await client.query(
//       `SELECT id, user_id, status, coins, amount_satang
//          FROM withdrawals WHERE id=$1 FOR UPDATE`,
//       [id]
//     );
//     if (wq.rowCount === 0) throw new Error('not_found');
//     const w = wq.rows[0];
//     if (w.status !== 'pending') throw new Error('invalid_status');

//     await client.query(
//       `UPDATE withdrawals
//          SET status='paid', admin_id=$2, admin_note=$3, paid_at=now()
//        WHERE id=$1`,
//       [id, adminId || null, note]
//     );

//     await client.query('COMMIT');

//     // 🔔 แจ้งเตือน USER ว่าอนุมัติแล้ว
//     try {
//       await notificationCtrl.createAndEmit(req.app, {
//         targetUserId: w.user_id,
//         actorId     : adminId || 0,
//         action      : 'withdraw_approved',
//         message     : `คำขอถอน ${w.coins} เหรียญของคุณได้รับการอนุมัติแล้ว`,
//         postId      : null,
//       });
//     } catch (e) {
//       console.warn('notify withdraw_approved failed:', e);
//     }

//     return res.json({ ok: true, withdrawal_id: id });
//   } catch (e) {
//     await client.query('ROLLBACK');
//     console.error('approve withdrawal error:', e);
//     const msg = String(e.message || e);
//     const code = msg === 'not_found' ? 404 :
//                  msg === 'invalid_status' ? 400 : 500;
//     return res.status(code).json({ error: msg });
//   } finally {
//     client.release();
//   }
// });

// // ============ ADMIN: ปฏิเสธถอน ============
// router.post('/api/admin/withdrawals/:id/reject', async (req, res) => {
//   const id = Number(req.params.id || 0);
//   const adminId = Number(req.body?.admin_id || 0);
//   const reason  = String(req.body?.reason || 'rejected');

//   if (!id) return res.status(400).json({ error: 'invalid_id' });

//   const client = await pool.connect();
//   try {
//     await client.query('BEGIN');

//     const wq = await client.query(
//       `SELECT id, user_id, coins, rate_satang_per_coin, amount_satang, status
//        FROM withdrawals WHERE id=$1 FOR UPDATE`,
//       [id]
//     );
//     if (wq.rowCount === 0) throw new Error('not_found');
//     const w = wq.rows[0];
//     if (w.status !== 'pending') throw new Error('invalid_status');

//     await client.query(
//       `UPDATE user_wallets
//          SET coins = coins + $2, updated_at = now()
//        WHERE user_id = $1`,
//       [w.user_id, w.coins]
//     );

//     await client.query(
//       `INSERT INTO wallet_transactions
//         (user_id, type, amount_satang, coins, rate_satang_per_coin, note, created_at)
//        VALUES ($1, 'refund_withdrawal', $2, $3, $4, $5, now())`,
//       [w.user_id, Number(w.amount_satang), Number(w.coins), Number(w.rate_satang_per_coin), reason]
//     );

//     await client.query(
//       `UPDATE withdrawals
//          SET status='rejected', admin_id=$2, admin_note=$3, rejected_at=now()
//        WHERE id=$1`,
//       [id, adminId || null, reason]
//     );

//     await client.query('COMMIT');

//     // 🔔 แจ้งเตือน USER ว่าถูกปฏิเสธ
//     try {
//       await notificationCtrl.createAndEmit(req.app, {
//         targetUserId: w.user_id,
//         actorId     : adminId || 0,
//         action      : 'withdraw_rejected',
//         message     : `คำขอถอนถูกปฏิเสธ: ${reason}`,
//         postId      : null,
//       });
//     } catch (e) {
//       console.warn('notify withdraw_rejected failed:', e);
//     }

//     return res.json({ ok: true, withdrawal_id: id });
//   } catch (e) {
//     await client.query('ROLLBACK');
//     console.error('reject withdrawal error:', e);
//     const msg = String(e.message || e);
//     const code = msg === 'not_found' ? 404 :
//                  msg === 'invalid_status' ? 400 : 500;
//     return res.status(code).json({ error: msg });
//   } finally {
//     client.release();
//   }
// });

// // ============ CONFIG (ขั้นต่ำ/ค่าธรรมเนียม) ============
// router.get('/api/withdrawals/config', (req, res) => {
//   const fee = Number(process.env.WITHDRAW_FEE_PERCENT || 5);
//   const min = Number(process.env.WITHDRAW_MIN_COINS || 100);
//   res.json({ fee_percent: fee, min_coins: min });
// });

// // (เก็บ endpoint create เดิมไว้ใช้เทส / mock)
// router.post('/create', upload.single('slip'), async (req, res, next) => {
//   try {
//     const userId = Number(req.body.user_id);
//     const coins = Number(req.body.coins || 0);

//     const feePercent = Number(process.env.WITHDRAW_FEE_PERCENT || 5);
//     const minCoins   = Number(process.env.WITHDRAW_MIN_COINS || 100);

//     if (!userId || !coins) {
//       return res.status(400).json({ message: 'missing user_id or coins' });
//     }
//     if (coins < minCoins) {
//       return res.status(400).json({ message: `ขั้นต่ำ ${minCoins} เหรียญ` });
//     }

//     const feeCoins = Math.floor((coins * feePercent) / 100);
//     const netCoins = coins - feeCoins;
//     if (netCoins <= 0) {
//       return res.status(400).json({ message: 'ยอดสุทธิไม่ถูกต้อง' });
//     }

//     const slipPath = req.file ? `/uploads/slips/${req.file.filename}` : null;

//     res.status(201).json({
//       withdrawal: {
//         id: 'new-id',
//         user_id: userId,
//         coins,
//         fee_coins: feeCoins,
//         net_coins: netCoins,
//         slip_path: slipPath,
//         status: 'pending',
//       },
//     });
//   } catch (err) {
//     next(err);
//   }
// });

// module.exports = router;
// routes/withdrawals.js
const express = require('express');
const path   = require('path');
const fs     = require('fs');
const multer = require('multer');
const pool   = require('../models/db');
const notification = require('../controllers/notificationController'); // <<< NEW

const router = express.Router();

const dir = path.join(process.cwd(), 'uploads', 'withdraw_qr');
fs.mkdirSync(dir, { recursive: true });

const upload = multer({ dest: path.join(process.cwd(), 'uploads', 'slips') });

async function getCoinRate(client) {
  const r = await client.query(
    `SELECT COALESCE(coin_rate_satang_per_coin, 100) AS rate
     FROM admin_settings WHERE id = 1`
  );
  return Number(r.rows[0]?.rate || 100);
}

// ====== user ส่งคำขอถอน ======
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

    const uw = await client.query(
      `SELECT coins FROM user_wallets WHERE user_id = $1 FOR UPDATE`,
      [userId]
    );
    const current = Number(uw.rows[0]?.coins || 0);
    if (current < coins) {
      throw new Error('insufficient_coins');
    }

    const rate         = await getCoinRate(client);
    const amountSatang = coins * rate;
    const rel          = '/' + path
      .relative(process.cwd(), req.file.path)
      .replace(/\\/g, '/');

    await client.query(
      `UPDATE user_wallets
         SET coins = coins - $2, updated_at = now()
       WHERE user_id = $1`,
      [userId, coins]
    );

    await client.query(
      `INSERT INTO wallet_transactions
        (user_id, type, amount_satang, coins, rate_satang_per_coin, note, created_at)
       VALUES ($1, 'debit_withdrawal', $2, $3, $4, 'withdraw request', now())`,
      [userId, amountSatang, coins, rate]
    );

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

// ====== ประวัติถอนของฉัน ======
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

// ====== admin: ดูรายการ pending ======
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

// ====== admin: อนุมัติถอน ======
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

    await client.query(
      `UPDATE withdrawals
         SET status='paid', admin_id=$2, admin_note=$3, paid_at=now()
       WHERE id=$1`,
      [id, adminId || null, note]
    );

    await client.query('COMMIT');

    // <<< NEW: create notification + emit
    try {
      await notification.createAndEmit(req.app, {
        targetUserId: w.user_id,
        actorId: adminId || w.user_id, // ถ้าไม่มี admin ก็ให้เป็นตัวเองไปก่อน
        action: 'withdraw_approved',
        message: 'คำขอถอนเหรียญของคุณได้รับการอนุมัติแล้ว',
        postId: null,
      });
    } catch (err) {
      console.warn('create withdraw approved notification failed:', err);
    }

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

// ====== admin: ปฏิเสธถอน ======
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

    // <<< NEW: notification เมื่อถูกปฏิเสธ
    try {
      await notification.createAndEmit(req.app, {
        targetUserId: w.user_id,
        actorId: adminId || w.user_id,
        action: 'withdraw_rejected',
        message: `คำขอถอนเหรียญของคุณถูกปฏิเสธ: ${reason}`,
        postId: null,
      });
    } catch (err) {
      console.warn('create withdraw rejected notification failed:', err);
    }

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

// ====== config ค่าธรรมเนียม/ขั้นต่ำ ======
router.get('/api/withdrawals/config', (req, res) => {
  const fee = Number(process.env.WITHDRAW_FEE_PERCENT || 5);
  const min = Number(process.env.WITHDRAW_MIN_COINS || 100);
  res.json({ fee_percent: fee, min_coins: min });
});

// mock /create เดิม (ถ้ายังใช้ที่อื่นอยู่)
router.post('/create', upload.single('slip'), async (req, res, next) => {
  try {
    const userId = Number(req.body.user_id);
    const coins = Number(req.body.coins || 0);

    const feePercent = Number(process.env.WITHDRAW_FEE_PERCENT || 5);
    const minCoins   = Number(process.env.WITHDRAW_MIN_COINS || 100);

    if (!userId || !coins) {
      return res.status(400).json({ message: 'missing user_id or coins' });
    }
    if (coins < minCoins) {
      return res.status(400).json({ message: `ขั้นต่ำ ${minCoins} เหรียญ` });
    }

    const feeCoins = Math.floor((coins * feePercent) / 100);
    const netCoins = coins - feeCoins;
    if (netCoins <= 0) {
      return res.status(400).json({ message: 'ยอดสุทธิไม่ถูกต้อง' });
    }

    const slipPath = req.file ? `/uploads/slips/${req.file.filename}` : null;

    res.status(201).json({
      withdrawal: {
        id: 'new-id',
        user_id: userId,
        coins,
        fee_coins: feeCoins,
        net_coins: netCoins,
        slip_path: slipPath,
        status: 'pending',
      },
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;