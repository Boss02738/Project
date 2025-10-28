// controllers/postController.js
const pool = require('../models/db');

const normalizeImagePaths = (files = []) =>
  (files || []).map(f => `/uploads/post_images/${f.filename}`);

/** ===================== CREATE POST ===================== */
const createPost = async (req, res) => {
  const client = await pool.connect();
  try {
    const { user_id, text, year_label, subject } = req.body;
    if (!user_id) return res.status(400).json({ message: 'ต้องมี user_id' });

    // รูป/ไฟล์แนบ
    const images = normalizeImagePaths(req.files?.images);
    let fileUrl = null;
    if (req.files?.file?.[0]) {
      fileUrl = `/uploads/post_files/${req.files.file[0].filename}`;
    }
    const firstImage = images.length ? images[0] : null;

    // ----- ราคา (กันเหนียว normalize อีกรอบ) -----
    let priceType = String(req.body.price_type || '').toLowerCase() === 'paid' ? 'paid' : 'free';
    let priceAmountSatang = 0;
    if (priceType === 'paid') {
      if (req.body.price_amount_satang != null) {
        priceAmountSatang = parseInt(req.body.price_amount_satang, 10) || 0;
      } else if (req.body.price_baht != null || req.body.priceBaht != null) {
        const baht = parseFloat(req.body.price_baht ?? req.body.priceBaht);
        priceAmountSatang = Number.isFinite(baht) ? Math.round(baht * 100) : 0;
      }
    }

    await client.query('BEGIN');

    const insertPost = `
      INSERT INTO public.posts
        (user_id, text, year_label, subject, image_url, file_url,
         price_type, price_amount_satang, created_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8, NOW())
      RETURNING id, user_id, text, year_label, subject, image_url, file_url,
                price_type, price_amount_satang, created_at
    `;
    const p = await client.query(insertPost, [
      user_id,
      text || null,
      year_label || null,
      subject || null,
      firstImage,
      fileUrl,
      priceType,
      priceAmountSatang,
    ]);
    const post = p.rows[0];

    if (images.length) {
      const values = [];
      const params = [];
      images.forEach((img, i) => {
        params.push(`($1, $${i + 2})`);
        values.push(img);
      });
      await client.query(
        `INSERT INTO public.post_images (post_id, image_url) VALUES ${params.join(',')}`,
        [post.id, ...values]
      );
    }

    await client.query('COMMIT');

    // ส่งกลับโพสต์พร้อม images[]
    const r = await client.query(
      `SELECT p.*,
              COALESCE(json_agg(pi.image_url ORDER BY pi.id)
                       FILTER (WHERE pi.id IS NOT NULL), '[]') AS images
         FROM public.posts p
         LEFT JOIN public.post_images pi ON pi.post_id = p.id
        WHERE p.id = $1
        GROUP BY p.id`,
      [post.id]
    );

    res.status(201).json(r.rows[0]);
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('createPost error:', e);
    res.status(500).json({ message: 'internal error' });
  } finally {
    client.release();
  }
};

/** ===================== FEED ===================== */
const getFeed = async (req, res) => {
  try {
    const viewerId = Number(req.query.user_id) || 0;

    const q = `
      SELECT 
        p.*,
        u.username,
        COALESCE(u.avatar_url,'') AS avatar_url,
        COALESCE(json_agg(pi.image_url) FILTER (WHERE pi.id IS NOT NULL), '[]') AS images,
        (SELECT COUNT(*)::int FROM public.likes    WHERE post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments WHERE post_id = p.id) AS comment_count,
        EXISTS (
          SELECT 1 FROM public.likes l 
          WHERE l.post_id = p.id AND l.user_id = $1
        ) AS liked_by_me
      FROM public.posts p
      JOIN public.users u ON u.id_user = p.user_id
 LEFT JOIN public.post_images pi ON pi.post_id = p.id
  GROUP BY p.id, u.username, u.avatar_url
  ORDER BY p.created_at DESC
    `;
    const { rows } = await pool.query(q, [viewerId]);
    res.json(rows);
  } catch (err) {
    console.error('getFeed error:', err);
    res.status(500).json({ message: 'Error loading feed' });
  }
};

/** ===================== BY SUBJECT ===================== */
const getPostsBySubject = async (req, res) => {
  const { subject } = req.query;
  const viewerId = Number(req.query.user_id) || 0;

  try {
    const q = `
      SELECT 
        p.*,
        u.username,
        COALESCE(u.avatar_url,'') AS avatar_url,
        COALESCE(json_agg(pi.image_url ORDER BY pi.id)
                 FILTER (WHERE pi.id IS NOT NULL), '[]') AS images,
        (SELECT COUNT(*)::int FROM public.likes    WHERE post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments WHERE post_id = p.id) AS comment_count,
        EXISTS (
          SELECT 1 FROM public.likes l 
          WHERE l.post_id = p.id AND l.user_id = $2
        ) AS liked_by_me
      FROM public.posts p
      JOIN public.users u ON u.id_user = p.user_id
 LEFT JOIN public.post_images pi ON pi.post_id = p.id
     WHERE ($1::text IS NULL OR p.subject = $1)
  GROUP BY p.id, u.username, u.avatar_url
  ORDER BY p.created_at DESC
    `;
    const r = await pool.query(q, [subject || null, viewerId]);
    res.json(r.rows);
  } catch (e) {
    console.error('getPostsBySubject error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

/** ===================== LIKE/UNLIKE ===================== */
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
      await pool.query('INSERT INTO public.likes(post_id, user_id) VALUES ($1,$2)', [postId, userId]);
      return res.json({ liked: true });
    }
  } catch (e) {
    console.error('toggleLike error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

/** ===================== COUNTS ===================== */
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

/** ===================== COMMENTS ===================== */
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

/** ===================== SAVE / UNSAVE ===================== */
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
      await pool.query('INSERT INTO public.saves(post_id, user_id) VALUES ($1,$2)', [postId, userId]);
      return res.json({ saved: true });
    }
  } catch (e) {
    console.error('toggleSave error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

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

const getSavedPosts = async (req, res) => {
  const userId = Number(req.query.user_id);
  if (!userId) return res.status(400).json({ message: 'missing user_id' });

  try {
    const q = `
      SELECT p.id, p.text, p.year_label, p.subject,
             p.image_url, p.file_url, p.created_at,
             p.price_type, p.price_amount_satang,                         -- << ราคา
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

/** ===================== POSTS BY USER ===================== */
const getPostsByUser = async (req, res) => {
  try {
    const uid = Number(req.params.id);
    const viewerId = Number(req.query.viewer_id) || 0;
    if (!uid) return res.status(400).json({ message: 'missing user id' });

    const q = `
      SELECT 
        p.*,
        u.username,
        COALESCE(u.avatar_url,'') AS avatar_url,
        COALESCE(json_agg(pi.image_url ORDER BY pi.id)
                 FILTER (WHERE pi.id IS NOT NULL), '[]') AS images,
        (SELECT COUNT(*)::int FROM public.likes    WHERE post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments WHERE post_id = p.id) AS comment_count,
        EXISTS (
          SELECT 1 FROM public.likes l 
          WHERE l.post_id = p.id AND l.user_id = $2
        ) AS liked_by_me
      FROM public.posts p
      JOIN public.users u ON u.id_user = p.user_id
 LEFT JOIN public.post_images pi ON pi.post_id = p.id
     WHERE p.user_id = $1
  GROUP BY p.id, u.username, u.avatar_url
  ORDER BY p.created_at DESC
    `;
    const r = await pool.query(q, [uid, viewerId]);
    res.json(r.rows);
  } catch (e) {
    console.error('getPostsByUser error:', e);
    res.status(500).json({ message: 'internal error' });
  }
};

/** ===================== DETAIL + ACCESS ===================== */
const getPostDetail = async (req, res) => {
  try {
    const postId   = Number(req.params.id);
    const viewerId = Number(req.query.userId || req.query.viewer_id) || 0;

    const { rows } = await pool.query(
      `SELECT id, user_id, text, year_label, subject,
              image_url, file_url,
              price_type, price_amount_satang, created_at
         FROM public.posts
        WHERE id=$1`,
      [postId]
    );
    const post = rows[0];
    if (!post) return res.status(404).json({ error: 'not_found' });

    let hasAccess = false;
    if (post.price_type !== 'paid') {
      hasAccess = true;
    } else if (viewerId && viewerId === post.user_id) {
      hasAccess = true;
    } else {
      // ถ้ามีตารางสิทธิ์ (post_access หรือ purchases ที่อนุมัติแล้ว) ให้เช็คที่นี่
      try {
        const acc = await pool.query(
          `SELECT 1 FROM post_access WHERE post_id=$1 AND user_id=$2 LIMIT 1`,
          [postId, viewerId]
        );
        hasAccess = acc.rowCount > 0;
      } catch {
        hasAccess = false;
      }
    }

    res.json({ post, hasAccess });
  } catch (e) {
    console.error('getPostDetail error:', e);
    res.status(500).json({ error: 'internal_error' });
  }
};

module.exports = {
  createPost,
  getFeed,
  getPostsBySubject,
  toggleLike,
  addComment,
  getComments,
  getPostCounts,
  toggleSave,
  getSavedStatus,
  getSavedPosts,
  getPostsByUser,
  getPostDetail,       // << เพิ่ม export
};
