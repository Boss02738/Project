// controllers/postController.js
const fs = require("fs");
const path = require("path");
const pool = require("../models/db");
const { createAndEmit } = require('./notificationController');

/* ----------------------- helpers ----------------------- */
const normalizeImagePaths = (files = []) =>
  (files || []).map((f) => `/uploads/post_images/${f.filename}`);

/* ===================== CREATE POST ===================== */
async function createPost(req, res) {
  const client = await pool.connect();
  try {
    const { user_id, text, year_label, subject } = req.body || {};
    if (!user_id) return res.status(400).json({ message: "ต้องมี user_id" });

    // รูป/ไฟล์แนบ (multer.fields([{name:'images'},{name:'file'}]))
    const images = normalizeImagePaths(req.files?.images);
    let fileUrl = null;
    if (req.files?.file?.[0]) {
      fileUrl = `/uploads/post_files/${req.files.file[0].filename}`;
    }
    const firstImage = images.length ? images[0] : null;

    // ราคา
    let priceType =
      String(req.body.price_type || "").trim().toLowerCase() === "paid"
        ? "paid"
        : "free";
    let priceAmountSatang = 0;
    if (priceType === "paid") {
      if (req.body.price_amount_satang != null) {
        priceAmountSatang = parseInt(req.body.price_amount_satang, 10) || 0;
      } else if (req.body.price_baht != null || req.body.priceBaht != null) {
        const baht = parseFloat(req.body.price_baht ?? req.body.priceBaht);
        priceAmountSatang = Number.isFinite(baht) ? Math.round(baht * 100) : 0;
      }
    }

    await client.query("BEGIN");

    const insertSql = `
      INSERT INTO public.posts
        (user_id, text, year_label, subject, image_url, file_url,
         price_type, price_amount_satang, created_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8, now())
      RETURNING id`;
    const ins = await client.query(insertSql, [
      user_id,
      text || null,
      year_label || null,
      subject || null,
      firstImage,
      fileUrl,
      priceType,
      priceAmountSatang,
    ]);
    const newId = ins.rows[0].id;

    if (images.length) {
      const values = [];
      const params = [];
      images.forEach((img, i) => {
        params.push(`($1,$${i + 2})`);
        values.push(img);
      });
      await client.query(
        `INSERT INTO public.post_images (post_id, image_url) VALUES ${params.join(",")}`,
        [newId, ...values]
      );
    }

    await client.query("COMMIT");

    // ส่งกลับโพสต์พร้อม images[]
    const r = await pool.query(
      `SELECT p.*,
              COALESCE(json_agg(pi.image_url ORDER BY pi.id)
                       FILTER (WHERE pi.id IS NOT NULL), '[]') AS images
         FROM public.posts p
         LEFT JOIN public.post_images pi ON pi.post_id = p.id
        WHERE p.id = $1
        GROUP BY p.id`,
      [newId]
    );
    return res.status(201).json(r.rows[0]);
  } catch (e) {
    // 🔧 FIX: rollback ให้ถูก transaction
    try { await client.query("ROLLBACK"); } catch {}
    console.error("createPost error:", e);
    return res.status(500).json({ message: "internal error" });
  } finally {
    client.release();
  }
}

/* ========================= FEED ======================== */
// กรองโพสต์ที่ถูกแบน + ส่ง is_banned กลับไป
async function getFeed(req, res) {
  try {
    const viewerId = Number(req.query.user_id || 0);

    const sql = `
      SELECT
        p.id,
        p.user_id,
        u.username,
        COALESCE(u.avatar_url,'') AS avatar_url,
        p.text, p.subject, p.year_label,
        LOWER(TRIM(p.price_type)) AS price_type,
        p.price_amount_satang,
        p.file_url,
        p.created_at,
        COALESCE(p.is_banned,false) AS is_banned,

        CASE
          WHEN $1 = 0 THEN false
          WHEN EXISTS (
            SELECT 1 FROM public.purchased_posts pp
            WHERE pp.post_id = p.id AND pp.user_id = $1
          ) THEN true
          ELSE false
        END AS is_purchased,

        (SELECT COUNT(*)::int FROM public.likes    WHERE post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments WHERE post_id = p.id) AS comment_count,

        CASE
          WHEN $1 = 0 THEN false
          WHEN EXISTS (
            SELECT 1 FROM public.likes l
            WHERE l.post_id = p.id AND l.user_id = $1
          ) THEN true
          ELSE false
        END AS liked_by_me,

        COALESCE(
          json_agg(pi.image_url ORDER BY pi.id)
            FILTER (WHERE pi.id IS NOT NULL),
          '[]'
        ) AS images

      FROM public.posts p
      JOIN public.users u ON u.id_user = p.user_id
      LEFT JOIN public.post_images pi ON pi.post_id = p.id
      WHERE COALESCE(p.is_archived,false) = false
        AND COALESCE(p.is_banned,false)  = false
      GROUP BY p.id, u.id_user, u.username, u.avatar_url
      ORDER BY p.created_at DESC
      LIMIT 50
    `;

    const { rows } = await pool.query(sql, [viewerId]);
    res.json(rows);
  } catch (e) {
    console.error('getFeed error', e);
    res.status(500).json({ message: 'Server error' });
  }
}

/* ===================== BY SUBJECT ===================== */
async function getPostsBySubject(req, res) {
  const { subject } = req.query;
  const viewerId = Number(req.query.user_id) || 0;
  try {
    const q = `
      SELECT 
        p.*,
        u.username,
        COALESCE(u.avatar_url,'') AS avatar_url,
        LOWER(TRIM(p.price_type)) AS price_type,
        COALESCE(p.is_banned,false) AS is_banned,
        COALESCE(json_agg(pi.image_url ORDER BY pi.id)
                FILTER (WHERE pi.id IS NOT NULL), '[]') AS images,
        (SELECT COUNT(*)::int FROM public.likes    WHERE post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments WHERE post_id = p.id) AS comment_count,
        EXISTS (
          SELECT 1 FROM public.likes l 
          WHERE l.post_id = p.id AND l.user_id = $2
        ) AS liked_by_me,
        EXISTS (
          SELECT 1 FROM public.purchased_posts pp
          WHERE pp.post_id = p.id
            AND pp.user_id = $2
        ) AS is_purchased
      FROM public.posts p
      JOIN public.users u ON u.id_user = p.user_id
      LEFT JOIN public.post_images pi ON pi.post_id = p.id
      WHERE COALESCE(p.is_archived,false) = false
        AND COALESCE(p.is_banned,false)  = false
        AND ($1::text IS NULL OR p.subject = $1)
      GROUP BY p.id, u.username, u.avatar_url
      ORDER BY p.created_at DESC
    `;
    const r = await pool.query(q, [subject || null, viewerId]);
    res.json(r.rows);
  } catch (e) {
    console.error("getPostsBySubject error:", e);
    res.status(500).json({ message: "internal error" });
  }
}

/* ===================== LIKE/UNLIKE ===================== */
async function toggleLike(req, res) {
  const userId = Number(req.body.user_id);
  const postId = Number(req.params.id || req.body.post_id);
  if (!userId || !postId) return res.status(400).json({ message: "bad_request" });

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    // หาเจ้าของโพสต์ไว้ส่ง noti
    const { rows: postRows } = await client.query(
      `SELECT id, user_id FROM public.posts WHERE id=$1`,
      [postId]
    );
    if (!postRows.length) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "post_not_found" });
    }
    const ownerId = Number(postRows[0].user_id);

    // เช็คว่าไลค์อยู่แล้วไหม
    const { rows: likeRows } = await client.query(
      `SELECT id FROM public.likes WHERE user_id=$1 AND post_id=$2`,
      [userId, postId]
    );

    let likedNow;
    if (likeRows.length) {
      // ถ้ามีอยู่แล้ว → unlike
      await client.query(`DELETE FROM public.likes WHERE id=$1`, [likeRows[0].id]);
      likedNow = false;
    } else {
      // ถ้ายัง → like
      await client.query(
        `INSERT INTO public.likes (user_id, post_id, created_at) VALUES ($1,$2,now())`,
        [userId, postId]
      );
      likedNow = true;

      // ส่งแจ้งเตือนให้เจ้าของโพสต์ (ห้ามส่งถ้าเจ้าของกดไลค์โพสต์ตัวเอง)
      if (ownerId && ownerId !== userId) {
        await createAndEmit(req.app, {
          targetUserId: ownerId,     // ผู้รับ
          actorId: userId,           // คนกดไลค์
          action: "like",            // คีย์ที่ NotificationScreen ใช้ได้
          message: "ถูกใจโพสต์ของคุณ",
          postId: postId,
        });
      }
    }

    await client.query("COMMIT");

    // นับ like ใหม่
    const { rows: cnt } = await pool.query(
      `SELECT COUNT(*)::int AS n FROM public.likes WHERE post_id=$1`,
      [postId]
    );

    return res.json({ ok: true, liked: likedNow, like_count: cnt[0].n });
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("toggleLike error:", e);
    return res.status(500).json({ message: "internal_error" });
  } finally {
    client.release();
  }
}
/* ========================= COUNTS ====================== */
async function getPostCounts(req, res) {
  const postId = Number(req.params.id);
  if (!postId) return res.status(400).json({ message: "missing post_id" });
  try {
    const {
      rows: [a],
    } = await pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM public.likes    WHERE post_id=$1) AS like_count,
         (SELECT COUNT(*)::int FROM public.comments WHERE post_id=$1) AS comment_count`,
      [postId]
    );
    res.json(a);
  } catch (e) {
    console.error("getPostCounts error:", e);
    res.status(500).json({ message: "internal error" });
  }
}

/* ========================= COMMENTS ==================== */
async function getComments(req, res) {
  const postId = Number(req.params.id);
  if (!postId) return res.status(400).json({ message: "missing post id" });
  try {
    const r = await pool.query(
      `SELECT c.id, c.text, c.created_at, c.user_id,
              u.username,
              COALESCE(u.avatar_url,'/uploads/avatars/default.png') AS avatar_url
         FROM public.comments c
         LEFT JOIN public.users u ON u.id_user = c.user_id
        WHERE c.post_id=$1
        ORDER BY c.created_at ASC`,
      [postId]
    );
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ message: "server error" });
  }
}

// async function addComment(req, res) {
//   const postId = Number(req.params.id);
//   const { user_id, text } = req.body || {};
//   const userId = Number(user_id);
//   if (!postId || !userId || !text || !text.trim())
//     return res.status(400).json({ message: "missing fields" });
//   try {
//     await pool.query(
//       "INSERT INTO public.comments(post_id,user_id,text) VALUES ($1,$2,$3)",
//       [postId, userId, text.trim()]
//     );
//     res.json({ message: "ok" });
//   } catch (e) {
//     console.error("addComment error:", e);
//     res.status(500).json({ message: "internal error" });
//   }
// }
async function addComment(req, res) {
  const userId = Number(req.body.user_id);
  const postId = Number(req.params.id || req.body.post_id);
  const text = (req.body.text || "").toString().trim();
  if (!userId || !postId || !text) {
    return res.status(400).json({ message: "bad_request" });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    // หาเจ้าของโพสต์ไว้ส่ง noti
    const { rows: postRows } = await client.query(
      `SELECT id, user_id FROM public.posts WHERE id=$1`,
      [postId]
    );
    if (!postRows.length) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "post_not_found" });
    }
    const ownerId = Number(postRows[0].user_id);

    // เพิ่มคอมเมนต์
    const { rows: ins } = await client.query(
      `INSERT INTO public.comments (user_id, post_id, text, created_at)
       VALUES ($1,$2,$3,now())
       RETURNING id, user_id, post_id, text, created_at`,
      [userId, postId, text]
    );

    // ส่ง noti ให้เจ้าของโพสต์ (ถ้าไม่ใช่คอมเมนต์ตัวเอง)
    if (ownerId && ownerId !== userId) {
      await createAndEmit(req.app, {
        targetUserId: ownerId,       // ผู้รับ
        actorId: userId,             // คนคอมเมนต์
        action: "comment",           // ให้ตรงกับฝั่งแอป
        message: "แสดงความคิดเห็นในโพสต์ของคุณ",
        postId: postId,
      });
    }

    await client.query("COMMIT");

    // นับคอมเมนต์ใหม่
    const { rows: cnt } = await pool.query(
      `SELECT COUNT(*)::int AS n FROM public.comments WHERE post_id=$1`,
      [postId]
    );

    return res.json({ ok: true, comment: ins[0], comment_count: cnt[0].n });
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("addComment error:", e);
    return res.status(500).json({ message: "internal_error" });
  } finally {
    client.release();
  }
}
/* ======================== SAVE ========================= */
async function toggleSave(req, res) {
  const postId = Number(req.params.id);
  const userId = Number(req.body.user_id);
  if (!postId || !userId)
    return res.status(400).json({ message: "missing post_id/user_id" });

  const chk = await pool.query(
    "SELECT COALESCE(is_archived,false) a, COALESCE(is_banned,false) b FROM public.posts WHERE id=$1",
    [postId]
  );
  if (!chk.rowCount) return res.status(404).json({ message: "post_not_found" });
  if (chk.rows[0].a) return res.status(400).json({ message: "post_archived" });
  if (chk.rows[0].b) return res.status(400).json({ message: "post_banned" });

  try {
    const ex = await pool.query(
      "SELECT id FROM public.saves WHERE post_id=$1 AND user_id=$2",
      [postId, userId]
    );
    if (ex.rowCount > 0) {
      await pool.query("DELETE FROM public.saves WHERE id=$1", [ex.rows[0].id]);
      return res.json({ saved: false });
    } else {
      await pool.query(
        "INSERT INTO public.saves(post_id,user_id) VALUES ($1,$2)",
        [postId, userId]
      );
      return res.json({ saved: true });
    }
  } catch (e) {
    console.error("toggleSave error:", e);
    res.status(500).json({ message: "internal error" });
  }
}

async function getSavedStatus(req, res) {
  const postId = Number(req.params.id);
  const userId = Number(req.query.user_id);
  if (!postId || !userId)
    return res.status(400).json({ message: "missing post_id/user_id" });

  try {
    const r = await pool.query(
      `SELECT 1
         FROM public.saves s
         JOIN public.posts p ON p.id = s.post_id
        WHERE s.post_id=$1 AND s.user_id=$2
          AND COALESCE(p.is_archived,false)=false
          AND COALESCE(p.is_banned,false)=false
        LIMIT 1`,
      [postId, userId]
    );
    res.json({ saved: r.rowCount > 0 });
  } catch (e) {
    console.error("getSavedStatus error:", e);
    res.status(500).json({ message: "internal error" });
  }
}

async function getSavedPosts(req, res) {
  const userId = Number(req.query.user_id);
  if (!userId) return res.status(400).json({ message: "missing user_id" });

  try {
    const q = `
      SELECT p.*,
             u.id_user AS user_id,
             u.username,
             COALESCE(u.avatar_url,'') AS avatar_url,
             COALESCE(p.is_banned,false) AS is_banned,
             COALESCE(json_agg(pi.image_url ORDER BY pi.id)
                      FILTER (WHERE pi.id IS NOT NULL), '[]') AS images,
             (SELECT COUNT(*)::int FROM public.likes    WHERE post_id=p.id) AS like_count,
             (SELECT COUNT(*)::int FROM public.comments WHERE post_id=p.id) AS comment_count,
             TRUE AS saved_by_me,
             EXISTS(SELECT 1 FROM public.likes l WHERE l.post_id=p.id AND l.user_id=$1) AS liked_by_me,
             s.created_at AS saved_at
        FROM public.saves s
        JOIN public.posts p ON p.id = s.post_id
        JOIN public.users u ON u.id_user = p.user_id
        LEFT JOIN public.post_images pi ON pi.post_id = p.id
       WHERE s.user_id=$1
         AND COALESCE(p.is_archived,false)=false
         AND COALESCE(p.is_banned,false)=false
       GROUP BY p.id, u.id_user, u.username, u.avatar_url, s.created_at
       ORDER BY s.created_at DESC`;
    const r = await pool.query(q, [userId]);
    res.json(r.rows);
  } catch (e) {
    console.error("getSavedPosts error:", e);
    res.status(500).json({ message: "internal error" });
  }
}

/* ===================== POSTS BY USER ==================== */
async function getPostsByUser(req, res) {
  try {
    const uid = Number(req.params.id);
    const viewerId = Number(req.query.viewer_id) || 0;
    if (!uid) return res.status(400).json({ message: "missing user id" });

    const q = `
      SELECT p.*,
             u.username,
             COALESCE(u.avatar_url,'') AS avatar_url,
             LOWER(TRIM(p.price_type)) AS price_type,
             COALESCE(p.is_banned,false) AS is_banned,
             COALESCE(json_agg(pi.image_url ORDER BY pi.id)
                      FILTER (WHERE pi.id IS NOT NULL), '[]') AS images,
             (SELECT COUNT(*)::int FROM public.likes    WHERE post_id=p.id) AS like_count,
             (SELECT COUNT(*)::int FROM public.comments WHERE post_id=p.id) AS comment_count,
             EXISTS (SELECT 1 FROM public.likes l WHERE l.post_id=p.id AND l.user_id=$2) AS liked_by_me
        FROM public.posts p
        JOIN public.users u ON u.id_user = p.user_id
        LEFT JOIN public.post_images pi ON pi.post_id = p.id
       WHERE p.user_id=$1
         AND COALESCE(p.is_archived,false)=false
         AND COALESCE(p.is_banned,false)=false
       GROUP BY p.id, u.username, u.avatar_url
       ORDER BY p.created_at DESC`;
    const r = await pool.query(q, [uid, viewerId]);
    res.json(r.rows);
  } catch (e) {
    console.error("getPostsByUser error:", e);
    res.status(500).json({ message: "internal error" });
  }
}

/* ===================== DETAIL + ACCESS ================== */
async function getPostDetail(req, res) {
  try {
    const postId  = Number(req.params.id);
    const viewerId =
      Number(req.query.user_id) ||
      Number(req.query.viewer_id) ||
      Number(req.query.userId) || 0;

    if (!postId) return res.status(400).json({ error: "missing_post_id" });

    const q = `
      SELECT
        p.id,
        p.user_id,
        u.username,
        COALESCE(u.avatar_url,'') AS avatar_url,
        p.text, p.subject, p.year_label,
        LOWER(TRIM(p.price_type)) AS price_type,
        p.price_amount_satang,
        p.file_url,
        p.created_at,
        COALESCE(p.is_archived,false) AS is_archived,
        COALESCE(p.is_banned,false)   AS is_banned,

        /* รูปเหมือนหน้า Home */
        COALESCE(
          json_agg(pi.image_url ORDER BY pi.id)
            FILTER (WHERE pi.id IS NOT NULL),
          '[]'
        ) AS images,

        /* นับยอด */
        (SELECT COUNT(*)::int FROM public.likes    WHERE post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments WHERE post_id = p.id) AS comment_count,

        /* คนดูคนนี้กดไลก์มั้ย */
        CASE
          WHEN $2 = 0 THEN false
          WHEN EXISTS (SELECT 1 FROM public.likes l WHERE l.post_id = p.id AND l.user_id = $2) THEN true
          ELSE false
        END AS liked_by_me,

        /* ซื้อแล้วหรือยัง (เอาไว้โชว์ badge) */
        CASE
          WHEN $2 = 0 THEN false
          WHEN EXISTS (SELECT 1 FROM public.purchased_posts pp WHERE pp.post_id = p.id AND pp.user_id = $2) THEN true
          ELSE false
        END AS is_purchased,

        /* สิทธิ์เข้าถึงไฟล์/รูปทั้งหมด */
        CASE
          WHEN LOWER(TRIM(p.price_type)) <> 'paid' THEN true
          WHEN $2 <> 0 AND ($2 = p.user_id
                OR EXISTS (SELECT 1 FROM public.purchased_posts pp WHERE pp.post_id = p.id AND pp.user_id = $2))
            THEN true
          ELSE false
        END AS has_access

      FROM public.posts p
      JOIN public.users u       ON u.id_user = p.user_id
      LEFT JOIN public.post_images pi ON pi.post_id = p.id
      WHERE p.id = $1
        AND COALESCE(p.is_banned,false) = false
      GROUP BY p.id, u.id_user, u.username, u.avatar_url
      LIMIT 1
    `;

    const { rows } = await pool.query(q, [postId, viewerId]);
    const row = rows[0];
    if (!row) return res.status(404).json({ error: "not_found" });

    // ถ้าโพสต์ถูก archive และคนดูไม่ใช่เจ้าของ → ซ่อน
    if (row.is_archived && Number(row.user_id) !== viewerId) {
      return res.status(404).json({ error: "not_found" });
    }

    // ส่งกลับ “โครงสร้างเดียวกับ feed” + access flags
    return res.json({
      ...row,
      // เผื่อ client เดิมคาดหวังชื่อ field นี้
      hasAccess: row.has_access,
    });
  } catch (e) {
    console.error("getPostDetail error:", e);
    res.status(500).json({ error: "internal_error" });
  }
}

/* ================= ARCHIVE / UNARCHIVE / DELETE ================ */
async function archivePost(req, res) {
  try {
    const postId = Number(req.params.id);
    const userId = Number(req.body.user_id);
    const { rows } = await pool.query(
      "UPDATE posts SET is_archived=true WHERE id=$1 AND user_id=$2 RETURNING *",
      [postId, userId]
    );
    if (!rows.length)
      return res.status(404).json({ error: "ไม่พบโพสต์หรือไม่มีสิทธิ์ลบ" });
    res.json({ message: "Archived", post: rows[0] });
  } catch (e) {
    console.error("archivePost error:", e);
    res.status(500).json({ error: "Server error" });
  }
}

async function unarchivePost(req, res) {
  try {
    const postId = Number(req.params.id);
    const userId = Number(req.body.user_id);
    if (!postId || !userId)
      return res.status(400).json({ message: "missing ids" });
    const { rows } = await pool.query(
      "UPDATE posts SET is_archived=false WHERE id=$1 AND user_id=$2 RETURNING *",
      [postId, userId]
    );
    if (!rows.length)
      return res.status(404).json({ message: "not_found_or_no_permission" });
    res.json({ message: "Unarchived", post: rows[0] });
  } catch (e) {
    console.error("unarchivePost error:", e);
    res.status(500).json({ message: "internal error" });
  }
}

async function hardDeletePost(req, res) {
  const postId = Number(req.params.id);
  if (!postId) return res.status(400).json({ message: "missing post_id" });

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const { rows } = await client.query(
      `SELECT image_url, file_url FROM public.posts WHERE id=$1`,
      [postId]
    );
    if (!rows.length) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "post not found" });
    }
    const { image_url, file_url } = rows[0];

    await client.query(`DELETE FROM public.posts WHERE id=$1`, [postId]);
    await client.query(`DELETE FROM public.post_images WHERE post_id=$1`, [postId]);

    await client.query("COMMIT");

    // ลบไฟล์บนดิสก์ (ถ้ามี)
    [image_url, file_url].filter(Boolean).forEach((p) => {
      const fp = path.join(process.cwd(), p);
      fs.unlink(fp, () => {});
    });

    res.json({ ok: true, message: "deleted" });
  } catch (e) {
    try { await client.query("ROLLBACK"); } catch {}
    console.error("hardDeletePost error:", e);
    res.status(500).json({ message: "internal error" });
  } finally {
    client.release();
  }
}

/* ===================== ARCHIVED LIST =================== */
async function getArchivedPosts(req, res) {
  try {
    const userId = Number(req.query.user_id);
    if (!userId) return res.status(400).json({ message: "missing user_id" });
    const q = `
      SELECT p.*,
             u.username,
             COALESCE(u.avatar_url,'') AS avatar_url,
             COALESCE(json_agg(pi.image_url ORDER BY pi.id)
                      FILTER (WHERE pi.id IS NOT NULL), '[]') AS images,
             (SELECT COUNT(*)::int FROM public.likes    WHERE post_id=p.id) AS like_count,
             (SELECT COUNT(*)::int FROM public.comments WHERE post_id=p.id) AS comment_count
        FROM public.posts p
        JOIN public.users u ON u.id_user = p.user_id
        LEFT JOIN public.post_images pi ON pi.post_id = p.id
       WHERE p.user_id=$1 AND p.is_archived=true
       GROUP BY p.id, u.username, u.avatar_url
       ORDER BY p.created_at DESC`;
    const r = await pool.query(q, [userId]);
    res.json(r.rows);
  } catch (e) {
    console.error("getArchivedPosts error:", e);
    res.status(500).json({ message: "internal error" });
  }
}

/* =================== PURCHASED FEED/LIST ================== */
const getPurchasedFeed = async (req, res) => {
  const userId = Number(req.query.user_id);
  if (!userId) return res.status(400).json({ message: 'ต้องมี user_id' });

  const client = await pool.connect();
  try {
    const sql = `
      SELECT 
        p.id,
        u.id_user AS user_id,
        u.username,
        COALESCE(u.avatar_url,'') AS avatar_url,
        p.text, p.subject, p.year_label,
        LOWER(TRIM(p.price_type)) AS price_type,
        COALESCE(p.is_banned,false) AS is_banned,
        p.price_amount_satang,
        p.file_url,
        p.created_at,
        COALESCE(
          json_agg(pi.image_url ORDER BY pi.id) FILTER (WHERE pi.id IS NOT NULL),
          '[]'
        ) AS images,
        (SELECT COUNT(*)::int FROM public.likes    WHERE post_id = p.id) AS like_count,
        (SELECT COUNT(*)::int FROM public.comments WHERE post_id = p.id) AS comment_count,
        EXISTS (
          SELECT 1 FROM public.likes l 
          WHERE l.post_id = p.id AND l.user_id = $1
        ) AS liked_by_me,
        pp.granted_at
      FROM public.purchased_posts pp
      JOIN public.posts  p ON p.id = pp.post_id
      JOIN public.users  u ON u.id_user = p.user_id
      LEFT JOIN public.post_images pi ON pi.post_id = p.id
      WHERE pp.user_id = $1
        AND COALESCE(p.is_banned,false)=false
      GROUP BY p.id, u.id_user, u.username, u.avatar_url, pp.granted_at
      ORDER BY pp.granted_at DESC NULLS LAST, p.created_at DESC;
    `;
    const { rows } = await client.query(sql, [userId]);
    return res.json(rows || []);
  } catch (err) {
    console.error('getPurchasedFeed error:', err);
    return res.status(500).json({ message: 'server error' });
  } finally {
    client.release();
  }
};

const getPurchasedPosts = async (req, res) => {
  const userId = Number(req.query.user_id);
  if (!userId) return res.status(400).json({ message: 'ต้องมี user_id' });

  const client = await pool.connect();
  try {
    const sql = `
      SELECT pp.post_id
      FROM public.purchased_posts pp
      JOIN public.posts p ON p.id = pp.post_id
      WHERE pp.user_id = $1
        AND COALESCE(p.is_banned,false)=false
      ORDER BY pp.granted_at DESC NULLS LAST;
    `;
    const { rows } = await client.query(sql, [userId]);
    return res.json(rows.map(r => r.post_id));
  } catch (err) {
    console.error('getPurchasedPosts error:', err);
    return res.status(500).json({ message: 'server error' });
  } finally {
    client.release();
  }
};

/* ============ SECURE DOWNLOAD & IMAGE ACCESS ============ */
async function downloadFileProtected(req, res) {
  try {
    const postId = Number(req.params.id);
    const userId = Number(req.query.user_id || 0);

    const { rows } = await pool.query(
      `SELECT id, user_id, LOWER(TRIM(price_type)) AS price_type, file_url,
              COALESCE(is_archived,false) AS is_archived,
              COALESCE(is_banned,false)   AS is_banned
       FROM public.posts WHERE id = $1`,
      [postId]
    );

    if (!rows.length || rows[0].is_archived || rows[0].is_banned) {
      return res.status(404).json({ message: "Post not found" });
    }
    const p = rows[0];
    if (!p.file_url) return res.status(404).json({ message: "No file" });

    let canDownload = false;
    if (p.price_type !== "paid") {
      canDownload = true;
    } else if (userId && userId === p.user_id) {
      canDownload = true;
    } else if (userId) {
      const r2 = await pool.query(
        `SELECT 1 FROM public.purchased_posts WHERE post_id=$1 AND user_id=$2 LIMIT 1`,
        [postId, userId]
      );
      canDownload = r2.rowCount > 0;
    }
    if (!canDownload) return res.status(403).json({ message: "Not purchased" });

    const rel = p.file_url.replace(/^\/?uploads\//, "");
    const filePath = path.join(process.cwd(), "uploads", rel);
    if (!fs.existsSync(filePath)) return res.status(404).json({ message: "File missing" });

    return res.download(filePath, path.basename(filePath));
  } catch (e) {
    console.error("downloadFileProtected error", e);
    res.status(500).json({ message: "Server error" });
  }
}

// รูปภาพตามสิทธิ์ (ถ้ายังไม่ซื้อให้ส่งเฉพาะรูปแรก)
async function getImagesRespectAccess(req, res) {
  try {
    const postId = Number(req.params.id);
    const userId = Number(req.query.user_id || 0);

    const pr = await pool.query(
      `SELECT id, user_id, LOWER(TRIM(price_type)) AS price_type,
              COALESCE(is_archived,false) AS is_archived,
              COALESCE(is_banned,false)   AS is_banned
       FROM public.posts WHERE id=$1`,
      [postId]
    );
    if (!pr.rows.length || pr.rows[0].is_archived || pr.rows[0].is_banned) {
      return res.status(404).json({ message: "Post not found" });
    }
    const post = pr.rows[0];

    const { rows: imgs } = await pool.query(
      `SELECT id, image_url FROM public.post_images WHERE post_id=$1 ORDER BY id`,
      [postId]
    );

    let canSeeAll = false;
    if (post.price_type !== "paid") {
      canSeeAll = true;
    } else if (userId && userId === post.user_id) {
      canSeeAll = true;
    } else if (userId) {
      const r2 = await pool.query(
        `SELECT 1 FROM public.purchased_posts WHERE post_id=$1 AND user_id=$2 LIMIT 1`,
        [postId, userId]
      );
      canSeeAll = r2.rowCount > 0;
    }

    const result = canSeeAll ? imgs : (imgs.length ? [imgs[0]] : []);
    res.json(result);
  } catch (e) {
    console.error("getImagesRespectAccess error", e);
    res.status(500).json({ message: "Server error" });
  }
}

/* ======================= EXPORTS ======================= */
module.exports = {
  createPost,
  getFeed,
  getPostsBySubject,
  toggleLike,
  getPostCounts,
  getComments,
  addComment,
  toggleSave,
  getSavedStatus,
  getSavedPosts,
  getPostsByUser,
  getPostDetail,
  archivePost,
  unarchivePost,
  hardDeletePost,
  getArchivedPosts,
  getPurchasedFeed,
  getPurchasedPosts,
  downloadFileProtected,
  getImagesRespectAccess,
};
