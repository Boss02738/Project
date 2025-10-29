const pool = require('../models/db');

exports.markPaid = async (req, res) => {
  const { id } = req.params; // payout_requests.id (UUID)
  const { admin_note } = req.body;
  const r = await pool.query(
    `UPDATE payout_requests
        SET status='paid', paid_at=now(), updated_at=now(),
            admin_note = COALESCE($2, admin_note)
      WHERE id=$1 AND status='pending' RETURNING id`,
    [id, admin_note]
  );
  if (!r.rowCount) return res.status(400).json({ error:'not pending or not found' });
  res.json({ ok:true });
};

exports.reject = async (req, res) => {
  const { id } = req.params;
  const { admin_note } = req.body;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query(
      `SELECT user_id, amount_satang_requested
         FROM payout_requests
        WHERE id=$1 AND status='pending' FOR UPDATE`,
      [id]
    );
    if (!rows.length) throw new Error('not pending or not found');

    const { user_id, amount_satang_requested } = rows[0];

    await client.query(
      `UPDATE payout_requests
          SET status='rejected', updated_at=now(), admin_note=$2
        WHERE id=$1`,
      [id, admin_note || 'rejected']
    );

    await client.query(
      `UPDATE users
          SET coin_balance_satang = coin_balance_satang + $1
        WHERE id_user=$2`,
      [amount_satang_requested, user_id]
    );

    await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount_satang, related_payout_id, note)
       VALUES ($1,'adjustment',$2,$3,$4)`,
      [user_id, amount_satang_requested, id, 'revert rejected payout']
    );

    await client.query('COMMIT');
    res.json({ ok:true });
  } catch (e) {
    await client.query('ROLLBACK');
    res.status(400).json({ error: e.message });
  } finally { client.release(); }
};
