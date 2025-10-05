const pool = require('../models/db');

// GET /api/search/users?q=bos
exports.searchUsers = async (req, res) => {
  try {
    const q = (req.query.q || '').trim();
    if (!q) return res.json([]);
    const r = await pool.query(
      `SELECT id_user, username,
              COALESCE(avatar_url, '/uploads/avatars/default.png') AS avatar_url
       FROM public.users
       WHERE username ILIKE $1
       ORDER BY username ASC
       LIMIT 20`,
      [`%${q}%`]
    );
    res.json(r.rows);
  } catch (err) {
    console.error('searchUsers error:', err);
    res.status(500).json({ message: 'server error' });
  }
};

// GET /api/search/subjects?q=prog
// ถ้ายังไม่มีตารางวิชา ใช้ subject จาก posts แบบ distinct
exports.searchSubjects = async (req, res) => {
  try {
    const q = (req.query.q || '').trim();
    if (!q) return res.json([]);
    const r = await pool.query(
      `SELECT DISTINCT subject
       FROM public.posts
       WHERE subject ILIKE $1
       ORDER BY subject ASC
       LIMIT 20`,
      [`%${q}%`]
    );
    res.json(r.rows.map(row => row.subject).filter(Boolean));
  } catch (err) {
    console.error('searchSubjects error:', err);
    res.status(500).json({ message: 'server error' });
  }
};
