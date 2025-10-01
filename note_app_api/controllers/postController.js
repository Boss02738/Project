// controllers/postController.js
const pool = require('../models/db');

const createPost = async (req, res) => {
  try {
    const { user_id, text, year_label, subject } = req.body;
    if (!user_id) return res.status(400).json({ message: 'ต้องมี user_id' });

    let imageUrl = null, fileUrl = null;
    if (req.files?.image?.[0]) {
      imageUrl = '/uploads/post_images/' + req.files.image[0].filename;
    }
    if (req.files?.file?.[0]) {
      fileUrl  = '/uploads/post_files/' + req.files.file[0].filename;
    }

    const r = await pool.query(
      `INSERT INTO public.posts(user_id,text,year_label,subject,image_url,file_url)
       VALUES ($1,$2,$3,$4,$5,$6)
       RETURNING id, created_at`,
      [user_id, text ?? null, year_label ?? null, subject ?? null, imageUrl, fileUrl]
    );

    res.json({
      message: 'โพสต์สำเร็จ',
      post_id: r.rows[0].id,
      created_at: r.rows[0].created_at
    });
  } catch (e) {
    console.error('createPost error:', e);
    res.status(500).json({ message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
};

const getFeed = async (req, res) => {
  try {
    const r = await pool.query(`
      SELECT p.id, p.text, p.year_label, p.subject, p.image_url, p.file_url, p.created_at,
             u.id_user AS user_id, u.username, COALESCE(u.avatar_url,'') AS avatar_url
      FROM public.posts p
      JOIN public.users u ON u.id_user = p.user_id
      ORDER BY p.created_at DESC
      LIMIT 100
    `);
    res.json(r.rows);
  } catch (e) {
    console.error('getFeed error:', e);
    res.status(500).json({ message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
};

module.exports = { createPost, getFeed };