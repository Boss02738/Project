const pool = require('../models/db');

exports.getSummary = async (req, res) => {
  const userId = Number(req.user?.id_user || req.query.user_id);
  if (!userId) return res.status(400).json({ error: 'user_id required' });

  const [u, tx] = await Promise.all([
    pool.query(`SELECT coin_balance_satang FROM users WHERE id_user=$1`, [userId]),
    pool.query(`SELECT id, type, amount_satang, related_purchase_id, related_payout_id, note, created_at
                  FROM wallet_transactions
                 WHERE user_id=$1
                 ORDER BY created_at DESC
                 LIMIT 100`, [userId])
  ]);
  if (!u.rows.length) return res.status(404).json({ error: 'user not found' });
  res.json({ coin_balance_satang: u.rows[0].coin_balance_satang, transactions: tx.rows });
};

exports.createPayoutRequest = async (req, res) => {
  const userId = Number(req.user?.id_user || req.body.user_id);
  const { amount_satang, promptpay_mobile } = req.body;
  if (!userId || !amount_satang || !promptpay_mobile) {
    return res.status(400).json({ error: 'user_id, amount_satang, promptpay_mobile required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: s } = await client.query(
      `SELECT fee_percent, min_payout_satang FROM admin_settings WHERE id=1`
    );
    const feePercent = s[0]?.fee_percent ?? 30;
    const minPayout = BigInt(s[0]?.min_payout_satang ?? 1000);

    const reqAmt = BigInt(amount_satang);
    if (reqAmt < minPayout) throw new Error('amount below minimum');

    const { rows: u } = await client.query(
      `SELECT coin_balance_satang FROM users WHERE id_user=$1 FOR UPDATE`, [userId]
    );
    if (!u.length) throw new Error('user not found');
    const balance = BigInt(u[0].coin_balance_satang);
    if (reqAmt <= 0n || reqAmt > balance) throw new Error('invalid amount');

    const fee = (reqAmt * BigInt(feePercent)) / 100n;
    const net = reqAmt - fee;

    const { rows: pr } = await client.query(
      `INSERT INTO payout_requests
        (user_id, amount_satang_requested, amount_satang_fee, amount_satang_net, promptpay_mobile)
       VALUES ($1,$2,$3,$4,$5)
       RETURNING id`,
      [userId, String(reqAmt), String(fee), String(net), String(promptpay_mobile)]
    );
    const payoutId = pr[0].id;

    await client.query(
      `UPDATE users
          SET coin_balance_satang = coin_balance_satang - $1
        WHERE id_user=$2`,
      [String(reqAmt), userId]
    );

    await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount_satang, related_payout_id, note)
       VALUES ($1,'debit_withdrawal',$2,$3,$4)`,
      [userId, '-' + String(reqAmt), payoutId, 'withdraw request']
    );

    await client.query('COMMIT');
    res.json({ ok:true, payout_id: payoutId, fee_percent: Number(feePercent) });
  } catch (e) {
    await client.query('ROLLBACK');
    res.status(400).json({ error: e.message });
  } finally { client.release(); }
};
