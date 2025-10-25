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
// exports.searchSubjects = async (req, res) => {
//   try {
//     const q = (req.query.q || '').trim();
//     if (!q) return res.json([]);
//     const r = await pool.query(
//       `SELECT DISTINCT subject
//        FROM public.posts
//        WHERE subject ILIKE $1
//        ORDER BY subject ASC
//        LIMIT 20`,
//       [`%${q}%`]
//     );
//     res.json(r.rows.map(row => row.subject).filter(Boolean));
//   } catch (err) {
//     console.error('searchSubjects error:', err);
//     res.status(500).json({ message: 'server error' });
//   }
// };

// exports.searchSubjects = async (req, res) => {
//   try {
//     const q = (req.query.q || '').trim();

//     let sql = `
//       SELECT DISTINCT subject
//       FROM public.posts
//       WHERE subject IS NOT NULL
//     `;
//     const params = [];

//     if (q) {
//       sql += ` AND subject ILIKE $1`;
//       params.push(`%${q}%`);
//     }

//     sql += ` ORDER BY subject ASC`;        // จะใส่ LIMIT 100 ก็ได้ถ้ากังวลปริมาณ

//     const r = await pool.query(sql, params);
//     // map ออกมาเป็น array<string> และกันค่า falsy อีกรอบ
//     const subjects = r.rows.map(row => row.subject).filter(Boolean);

//     return res.json(subjects);
//   } catch (err) {
//     console.error('searchSubjects error:', err);
//     return res.status(500).json({ message: 'server error' });
//   }
// };

// controllers/searchController.js

// GET /api/search/subjects?q=...&year_label=ปี 1
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
