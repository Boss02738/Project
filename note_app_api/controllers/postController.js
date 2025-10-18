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
    const uid = Number(req.query.user_id) || 0;

    const r = await pool.query(`
      SELECT 
        p.id, p.text, p.year_label, p.subject, p.image_url, p.file_url, p.created_at,
        u.id_user AS user_id, u.username, COALESCE(u.avatar_url,'') AS avatar_url,
        (SELECT COUNT(*)::int FROM public.likes    WHERE post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments WHERE post_id = p.id) AS comment_count,
        CASE 
          WHEN $1 > 0 AND EXISTS(
            SELECT 1 FROM public.likes l WHERE l.post_id = p.id AND l.user_id = $1
          ) THEN true ELSE false 
        END AS liked_by_me
      FROM public.posts p
      JOIN public.users u ON u.id_user = p.user_id
      ORDER BY p.created_at DESC
      LIMIT 100
    `, [uid]);

    res.json(r.rows);
  } catch (e) {
    console.error('getFeed error:', e);
    res.status(500).json({ message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
};
const getPostsBySubject = async (req, res) => {
  try {
    const subject = decodeURIComponent(req.params.subject || '');
    const userId = Number(req.query.user_id || 0);

    const q = `
      SELECT 
        p.id, p.text, p.image_url, p.file_url, p.subject, p.year_label, p.created_at,
        u.username, COALESCE(u.avatar_url,'') AS avatar_url,
        -- นับ like / comment
        (SELECT COUNT(*)::int FROM public.likes    l WHERE l.post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments c WHERE c.post_id = p.id) AS comment_count,
        -- liked_by_me
        CASE WHEN $2 > 0 AND EXISTS (
          SELECT 1 FROM public.likes l2 WHERE l2.post_id = p.id AND l2.user_id = $2
        ) THEN TRUE ELSE FALSE END AS liked_by_me
      FROM public.posts p
      JOIN public.users u ON u.id_user = p.user_id
      WHERE p.subject ILIKE $1
      ORDER BY p.created_at DESC
    `;
    const r = await pool.query(q, [`%${subject}%`, userId || 0]);
    res.json(r.rows);
  } catch (err) {
    console.error('getPostsBySubject error:', err);
    res.status(500).json({ message: 'internal error' });
  }
};

//like/unlike+counts+comment
 const toggleLike = async (req, res) => {
  const postId = Number(req.params.id);
  const userId = Number(req.body.user_id);
  if (!postId || !userId) return res.status(400).json({ message: 'missing post_id/user_id' });

  try {
    const existing = await pool.query(
      'SELECT id FROM public.likes WHERE post_id=$1 AND user_id=$2',
      [postId, userId]
    );
    if (existing.rowCount > 0) {
      await pool.query('DELETE FROM public.likes WHERE id=$1', [existing.rows[0].id]);
      return res.json({ liked: false });
    } else {
      await pool.query(
        'INSERT INTO public.likes(post_id, user_id) VALUES ($1,$2)',
        [postId, userId]
      );
      return res.json({ liked: true });
    }
  } catch (e) {
    console.error('toggleLike error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

/** GET /posts/:id/counts */
const getPostCounts = async (req, res) => {
  const postId = Number(req.params.id);
  if (!postId) return res.status(400).json({ message: 'missing post_id' });

  try {
    const { rows: [a] } = await pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM public.likes WHERE post_id=$1) AS like_count,
         (SELECT COUNT(*)::int FROM public.comments WHERE post_id=$1) AS comment_count`,
      [postId]
    );
    res.json(a);
  } catch (e) {
    console.error('getPostCounts error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

/** GET /posts/:id/comments */
const getComments = async (req, res) => {
  const postId = Number(req.params.id);
  if (!postId) return res.status(400).json({ message: 'missing post id' });

  try {
    const r = await pool.query(
      `SELECT c.id, c.text, c.created_at,
              c.user_id,
              u.username,
              COALESCE(u.avatar_url, '/uploads/avatars/default.png') AS avatar_url
       FROM public.comments c
       LEFT JOIN public.users u ON u.id_user = c.user_id
       WHERE c.post_id = $1
       ORDER BY c.created_at ASC`,
      [postId]
    );
    return res.json(r.rows);
  } catch (err) {
    return res.status(500).json({ message: 'server error' });
  }
};

/** POST /posts/:id/comments  {user_id, text} */
const addComment = async (req, res) => {
  const postId = Number(req.params.id);
  const { user_id, text } = req.body || {};
  const userId = Number(user_id);
  if (!postId || !userId || !text || !text.trim()) {
    return res.status(400).json({ message: 'missing fields' });
  }
  try {
    await pool.query(
      'INSERT INTO public.comments(post_id, user_id, text) VALUES ($1,$2,$3)',
      [postId, userId, text.trim()]
    );
    res.json({ message: 'ok' });
  } catch (e) {
    console.error('addComment error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};
// === Save / Unsave (toggle) ===
const toggleSave = async (req, res) => {
  const postId = Number(req.params.id);
  const userId = Number(req.body.user_id);
  if (!postId || !userId) return res.status(400).json({ message: 'missing post_id/user_id' });

  try {
    const existing = await pool.query(
      'SELECT id FROM public.saves WHERE post_id=$1 AND user_id=$2',
      [postId, userId]
    );
    if (existing.rowCount > 0) {
      await pool.query('DELETE FROM public.saves WHERE id=$1', [existing.rows[0].id]);
      return res.json({ saved: false });
    } else {
      await pool.query(
        'INSERT INTO public.saves(post_id, user_id) VALUES ($1,$2)',
        [postId, userId]
      );
      return res.json({ saved: true });
    }
  } catch (e) {
    console.error('toggleSave error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

// === เช็คสถานะบันทึกของโพสต์นี้สำหรับ user นี้ ===
const getSavedStatus = async (req, res) => {
  const postId = Number(req.params.id);
  const userId = Number(req.query.user_id);
  if (!postId || !userId) return res.status(400).json({ message: 'missing post_id/user_id' });

  try {
    const r = await pool.query(
      'SELECT 1 FROM public.saves WHERE post_id=$1 AND user_id=$2 LIMIT 1',
      [postId, userId]
    );
    res.json({ saved: r.rowCount > 0 });
  } catch (e) {
    console.error('getSavedStatus error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

// === ดึงฟีดโพสต์ที่ user นี้บันทึกไว้ ===
const getSavedPosts = async (req, res) => {
  const userId = Number(req.query.user_id);
  if (!userId) return res.status(400).json({ message: 'missing user_id' });

  try {
    const q = `
      SELECT p.id, p.text, p.year_label, p.subject, p.image_url, p.file_url, p.created_at,
             u.id_user AS user_id, u.username, COALESCE(u.avatar_url,'') AS avatar_url
      FROM public.saves s
      JOIN public.posts p ON p.id = s.post_id
      JOIN public.users u ON u.id_user = p.user_id
      WHERE s.user_id=$1
      ORDER BY s.created_at DESC
    `;
    const r = await pool.query(q, [userId]);
    res.json(r.rows);
  } catch (e) {
    console.error('getSavedPosts error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

module.exports = { createPost, getFeed, getPostsBySubject, toggleLike, addComment, getComments, getPostCounts,toggleSave, getSavedStatus, getSavedPosts };