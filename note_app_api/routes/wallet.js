const express = require('express');
const pool = require('../models/db');

const router = express.Router();

function getUserId(req) {
  return req.user?.id ?? Number(req.query.user_id || req.body?.user_id);
}

router.get('/api/wallet', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(400).json({ error: 'invalid_user' });
  try {
    const q = await pool.query(`
      SELECT coins FROM user_wallets WHERE user_id = $1,
      [userId]`
    );
    const coins = q.rowCount ? Number(q.rows[0].coins) : 0;
    return res.json({ coins });
  } catch (e) {
    console.error('wallet get error:', e);
    return res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
