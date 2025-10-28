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

exports.searchSubjects = async (req, res) => {
  try {
    const q = (req.query.q || '').trim();           // คำค้น (อาจว่าง)
    const yearLabel = (req.query.year_label || '').trim(); // ปี (อาจว่าง)

    // สร้าง where + params แบบ dynamic
    const where = [];
    const params = [];

    // กรองเฉพาะโพสต์ที่ subject ไม่เป็น null/ว่าง
    where.push(`subject IS NOT NULL AND subject <> ''`);

    if (q) {
      params.push(`%${q}%`);
      where.push(`subject ILIKE $${params.length}`);
    }
    if (yearLabel) {
      params.push(yearLabel);
      where.push(`year_label = $${params.length}`);
    }

    const sql = `
      SELECT DISTINCT subject
      FROM public.posts
      WHERE ${where.length ? where.join(' AND ') : 'TRUE'}
      ORDER BY subject ASC
      LIMIT 100
    `;

    const r = await pool.query(sql, params);
    res.json(r.rows.map(row => row.subject).filter(Boolean));
  } catch (err) {
    console.error('searchSubjects error:', err);
    res.status(500).json({ message: 'server error' });
  }
};
