const pool = require('../models/db');

exports.getPurchasedPosts = async (req, res) => {
  const userId = Number(req.params.id);
  const { rows } = await pool.query(
    `SELECT pa.post_id, pa.granted_at, p.text, p.price_type, p.price_amount_satang,
            p.image_url, p.created_at, p.user_id AS seller_id
       FROM post_access pa
       JOIN posts p ON p.id = pa.post_id
      WHERE pa.user_id = $1
      ORDER BY pa.granted_at DESC
      LIMIT 100`,
    [userId]
  );
  res.json(rows);
};
