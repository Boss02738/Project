const pool = require('../models/db');

exports.decidePurchase = async (req, res) => {
  const id = Number(req.params.id);                 
  const { decision, admin_note } = req.body;      
  if (!['approved','rejected'].includes(decision)) {
    return res.status(400).json({ error: 'invalid decision' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query(
      `SELECT id, post_id, buyer_id, seller_id, amount_satang, status
         FROM purchases WHERE id=$1 FOR UPDATE`,
      [id]
    );
    if (!rows.length) throw new Error('purchase not found');
    const pu = rows[0];
    if (['approved','rejected','expired'].includes(pu.status)) {
      throw new Error(`invalid state: ${pu.status}`);
    }

    await client.query(
      `UPDATE purchases SET status=$1 WHERE id=$2`,
      [decision, id]
    );

    if (decision === 'approved') {
      await client.query(
        `INSERT INTO post_access (post_id, user_id)
         VALUES ($1,$2) ON CONFLICT (post_id,user_id) DO NOTHING`,
        [pu.post_id, pu.buyer_id]
      );
      await client.query(
        `INSERT INTO wallet_transactions (user_id, type, amount_satang, related_purchase_id, note)
         VALUES ($1,'credit_purchase',$2,$3,$4)`,
        [pu.seller_id, pu.amount_satang, pu.id, admin_note || 'credit from approved purchase']
      );
      await client.query(
        `UPDATE users SET coin_balance_satang = coin_balance_satang + $1
         WHERE id_user=$2`,
        [pu.amount_satang, pu.seller_id]
      );
    }

    await client.query('COMMIT');
    res.json({ ok:true, decision });
  } catch (e) {
    await client.query('ROLLBACK');
    res.status(400).json({ error: e.message });
  } finally { client.release(); }
};
