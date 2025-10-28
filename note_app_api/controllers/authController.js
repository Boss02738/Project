// controllers/authController.js
const bcrypt = require('bcrypt');
const pool = require('../models/db');
const { genOTP } = require('../utils/otp');
const { sendOTP } = require('../utils/mailer');

/* ---------------- CONFIG ---------------- */
const OTP_EXPIRE_MIN = Number(process.env.OTP_EXPIRE_MIN || 5);
const RESEND_COOLDOWN = Number(process.env.OTP_RESEND_COOLDOWN_SEC || 60);

/* ---------------- HELPERS ---------------- */
const isValidKuEmail = (email) => /^[^@]+@ku\.th$/i.test(String(email || '').trim());
const normEmail = (email) => String(email || '').trim().toLowerCase();
const normGender = (g) => {
  const s = String(g || '').trim().toLowerCase();
  return s && ['male', 'female', 'other'].includes(s) ? s : null;
};
const cleanPhone = (p) => {
  const digits = String(p || '').replace(/[^\d]/g, '');
  return digits.length ? digits : null;
};

/* =============================
   STEP 1: Request OTP
   ============================= */
const startRegister = async (req, res) => {
  const username = String(req.body.username || '').trim();
  const email = normEmail(req.body.email);
  const password = String(req.body.password || '');

  if (!username || !email || !password)
    return res.status(400).json({ message: 'กรอก username, email, password ให้ครบ' });
  if (!isValidKuEmail(email))
    return res.status(400).json({ message: 'อนุญาตเฉพาะอีเมล @ku.th เท่านั้น' });

  try {
    const dupeUser = await pool.query('SELECT 1 FROM public.users WHERE username=$1', [username]);
    if (dupeUser.rowCount > 0) return res.status(409).json({ message: 'Username นี้ถูกใช้แล้ว' });

    const dupeEmail = await pool.query('SELECT 1 FROM public.users WHERE email=$1', [email]);
    if (dupeEmail.rowCount > 0) return res.status(409).json({ message: 'อีเมลนี้ถูกใช้แล้ว' });

    // cooldown
    const last = await pool.query(
      `SELECT created_at FROM public.verification_password
       WHERE email=$1 AND purpose='register'
       ORDER BY created_at DESC LIMIT 1`,
      [email]
    );
    if (last.rowCount > 0) {
      const diff = (Date.now() - new Date(last.rows[0].created_at).getTime()) / 1000;
      if (diff < RESEND_COOLDOWN) {
        return res.status(429).json({
          message: `ขอ OTP ได้อีกใน ${Math.ceil(RESEND_COOLDOWN - diff)} วิ`,
          retry_after_sec: Math.ceil(RESEND_COOLDOWN - diff),
        });
      }
    }

    const otp = genOTP(6);
    const now = new Date();
    const expiresAt = new Date(now.getTime() + OTP_EXPIRE_MIN * 60 * 1000);

    await pool.query(`DELETE FROM public.verification_password WHERE email=$1 AND purpose='register'`, [email]);
    await pool.query(
      `INSERT INTO public.verification_password(email, otp, purpose, expires_at)
       VALUES ($1,$2,'register',$3)`,
      [email, otp, expiresAt]
    );

    await sendOTP(email, otp, OTP_EXPIRE_MIN);
    return res.json({
      message: 'ส่ง OTP แล้ว กรุณาตรวจอีเมล',
      email, ttl_min: OTP_EXPIRE_MIN, now: now.toISOString(),
      expiresAt: expiresAt.toISOString(), resend_after_sec: RESEND_COOLDOWN,
    });
  } catch (err) {
    console.error('startRegister error:', err);
    return res.status(500).json({ message: 'internal_error' });
  }
};

/* =============================
   STEP 2: Verify OTP & Register
   ============================= */
const verifyRegister = async (req, res) => {
  const username = String(req.body.username || '').trim();
  const email = normEmail(req.body.email);
  const password = String(req.body.password || '');
  const otp = String(req.body.otp || '').trim();

  if (!username || !email || !password || !otp)
    return res.status(400).json({ message: 'กรอกข้อมูลให้ครบ' });
  if (!isValidKuEmail(email))
    return res.status(400).json({ message: 'อนุญาตเฉพาะอีเมล @ku.th เท่านั้น' });

  try {
    const q = await pool.query(
      `SELECT id, expires_at
         FROM public.verification_password
        WHERE email=$1 AND otp=$2 AND purpose='register'
        ORDER BY created_at DESC LIMIT 1`,
      [email, otp]
    );
    if (q.rowCount === 0) return res.status(400).json({ message: 'OTP ไม่ถูกต้อง' });
    if (new Date(q.rows[0].expires_at).getTime() < Date.now())
      return res.status(400).json({ message: 'OTP หมดอายุแล้ว' });

    const dupeUser = await pool.query('SELECT 1 FROM public.users WHERE username=$1', [username]);
    if (dupeUser.rowCount > 0) return res.status(409).json({ message: 'Username นี้ถูกใช้แล้ว' });
    const dupeEmail = await pool.query('SELECT 1 FROM public.users WHERE email=$1', [email]);
    if (dupeEmail.rowCount > 0) return res.status(409).json({ message: 'อีเมลนี้ถูกใช้แล้ว' });

    const hash = await bcrypt.hash(password, 10);
    await pool.query(
      `INSERT INTO public.users(username, password, email, email_verified, profile_completed)
       VALUES ($1,$2,$3,true,false)`,
      [username, hash, email]
    );

    await pool.query('DELETE FROM public.verification_password WHERE id=$1', [q.rows[0].id]);
    return res.json({ message: 'สมัครสำเร็จ' });
  } catch (err) {
    console.error('verifyRegister error:', err);
    return res.status(500).json({ message: 'internal_error' });
  }
};

/* =============================
   STEP 3: Resend OTP
   ============================= */
const resendOtp = async (req, res) => {
  const email = normEmail(req.body.email);
  if (!email) return res.status(400).json({ message: 'ต้องใส่ email' });
  if (!isValidKuEmail(email))
    return res.status(400).json({ message: 'อนุญาตเฉพาะอีเมล @ku.th เท่านั้น' });

  try {
    const u = await pool.query('SELECT 1 FROM public.users WHERE email=$1', [email]);
    if (u.rowCount > 0) return res.status(409).json({ message: 'อีเมลนี้สมัครแล้ว' });

    const last = await pool.query(
      `SELECT created_at FROM public.verification_password
        WHERE email=$1 AND purpose='register'
        ORDER BY created_at DESC LIMIT 1`,
      [email]
    );
    if (last.rowCount > 0) {
      const diff = (Date.now() - new Date(last.rows[0].created_at).getTime()) / 1000;
      if (diff < RESEND_COOLDOWN) {
        return res.status(429).json({
          message: `ขอ OTP ได้อีกใน ${Math.ceil(RESEND_COOLDOWN - diff)} วิ`,
          retry_after_sec: Math.ceil(RESEND_COOLDOWN - diff),
        });
      }
    }

    const otp = genOTP(6);
    const now = new Date();
    const expiresAt = new Date(now.getTime() + OTP_EXPIRE_MIN * 60 * 1000);

    await pool.query(`DELETE FROM public.verification_password WHERE email=$1 AND purpose='register'`, [email]);
    await pool.query(
      `INSERT INTO public.verification_password(email, otp, purpose, expires_at)
       VALUES ($1,$2,'register',$3)`,
      [email, otp, expiresAt]
    );
    await sendOTP(email, otp, OTP_EXPIRE_MIN);

    return res.json({
      message: 'ส่ง OTP ใหม่แล้ว',
      email, ttl_min: OTP_EXPIRE_MIN, now: now.toISOString(),
      expiresAt: expiresAt.toISOString(), resend_after_sec: RESEND_COOLDOWN,
    });
  } catch (err) {
    console.error('resendOtp error:', err);
    return res.status(500).json({ message: 'internal_error' });
  }
};

/* =============================
   LOGIN
   ============================= */
const login = async (req, res) => {
  const email = normEmail(req.body.email);
  const password = String(req.body.password || '');

  if (!email || !password)
    return res.status(400).json({ message: 'กรอกอีเมลและรหัสผ่าน' });

  try {
    const r = await pool.query('SELECT * FROM public.users WHERE email=$1', [email]);
    if (r.rowCount === 0) return res.status(401).json({ message: 'ไม่พบบัญชีนี้' });

    const u = r.rows[0];
    if (!u.email_verified) return res.status(403).json({ message: 'กรุณายืนยันอีเมลก่อน' });

    const ok = await bcrypt.compare(password, u.password);
    if (!ok) return res.status(401).json({ message: 'รหัสผ่านไม่ถูกต้อง' });

    const needProfile = (u.profile_completed !== undefined) ? !u.profile_completed : (!u.bio || !u.gender);
    const avatarUrl = (u.avatar_url && String(u.avatar_url).trim() !== '')
      ? u.avatar_url
      : '/uploads/avatars/default.png';

    return res.json({
      message: 'เข้าสู่ระบบสำเร็จ',
      user: { id: u.id_user, username: u.username, email: u.email, avatar_url: avatarUrl },
      needProfile,
    });
  } catch (err) {
    console.error('login error:', err);
    return res.status(500).json({ message: 'internal_error' });
  }
};

/* =============================
   UPDATE PROFILE (by email)
   ============================= */
const updateProfile = async (req, res) => {
  try {
    const email = normEmail(req.body.email);
    if (!email) return res.status(400).json({ message: 'ต้องมี email' });

    const bio = (req.body.bio || '').toString().trim() || null;
    const gender = normGender(req.body.gender);
    const phone = cleanPhone(req.body.phone);

    // ตรวจว่ามีผู้ใช้อยู่จริง
    const u = await pool.query('SELECT id_user FROM public.users WHERE email=$1 LIMIT 1', [email]);
    if (u.rowCount === 0) return res.status(404).json({ message: 'ไม่พบบัญชีนี้' });

    const q = await pool.query(
      `UPDATE public.users
          SET bio = COALESCE($2, bio),
              gender = COALESCE($3, gender),
              phone = COALESCE($4, phone),
              profile_completed = true
        WHERE email = $1
        RETURNING id_user, username, email,
                  COALESCE(avatar_url, '/uploads/avatars/default.png') AS avatar_url,
                  bio, gender, phone, profile_completed`,
      [email, bio, gender, phone]
    );

    return res.json({ message: 'อัปเดตโปรไฟล์สำเร็จ', user: q.rows[0] });
  } catch (err) {
    console.error('updateProfile error:', err);
    return res.status(500).json({ message: 'internal_error' });
  }
};

/* =============================
   UPDATE PROFILE (by id_user)  <-- ใช้กับ /api/users/:id/profile
   ============================= */
const updateProfileById = async (req, res) => {
  try {
    const userId = Number(req.params.id);
    if (!userId) return res.status(400).json({ message: 'invalid user id' });

    const bio = (req.body.bio || '').toString().trim() || null;
    const gender = normGender(req.body.gender);
    const phone = cleanPhone(req.body.phone);

    const q = await pool.query(
      `UPDATE public.users
          SET bio = COALESCE($2, bio),
              gender = COALESCE($3, gender),
              phone = COALESCE($4, phone),
              profile_completed = true
        WHERE id_user = $1
        RETURNING id_user, username, email,
                  COALESCE(avatar_url, '/uploads/avatars/default.png') AS avatar_url,
                  bio, gender, phone, profile_completed`,
      [userId, bio, gender, phone]
    );

    if (q.rowCount === 0) return res.status(404).json({ message: 'user not found' });
    return res.json({ message: 'อัปเดตโปรไฟล์สำเร็จ', user: q.rows[0] });
  } catch (err) {
    console.error('POST /api/users/:id/profile error:', err);
    return res.status(500).json({ message: 'internal_error' });
  }
};

/* =============================
   UPLOAD AVATAR
   ============================= */
const uploadAvatar = async (req, res) => {
  try {
    const email = normEmail(req.body.email);
    if (!email) return res.status(400).json({ message: 'ต้องส่ง email มาด้วย' });
    if (!req.file) return res.status(400).json({ message: 'ไม่พบไฟล์รูป (avatar)' });

    const u = await pool.query('SELECT id_user FROM public.users WHERE email=$1', [email]);
    if (u.rowCount === 0) return res.status(404).json({ message: 'ไม่พบบัญชีนี้' });

    const fileUrl = `/uploads/avatars/${req.file.filename}`;
    await pool.query('UPDATE public.users SET avatar_url=$2 WHERE email=$1', [email, fileUrl]);

    return res.json({ ok: true, message: 'อัปโหลดรูปสำเร็จ', avatar_url: fileUrl });
  } catch (err) {
    console.error('uploadAvatar error:', err);
    return res.status(500).json({ message: 'อัปโหลดรูปไม่สำเร็จ' });
  }
};

const getUserBrief = async (req, res) => {
  try {
    const { id } = req.params;
    const r = await pool.query(
      `SELECT
          u.id_user,
          u.username,
          u.email,
          COALESCE(u.bio, '') AS bio,
          COALESCE(u.gender, '') AS gender,
          COALESCE(u.avatar_url, '/uploads/avatars/default.png') AS avatar_url,
          COALESCE(u.profile_completed, false) AS profile_completed,
          COALESCE(u.phone, '') AS phone,
          (SELECT COUNT(*)::int FROM public.posts p WHERE p.user_id = u.id_user) AS post_count
        FROM public.users u
       WHERE u.id_user = $1
       LIMIT 1`,
      [id]
    );
    if (r.rowCount === 0) return res.status(404).json({ message: 'user not found' });
    return res.json(r.rows[0]);
  } catch (err) {
    console.error('getUserBrief error:', err);
    return res.status(500).json({ message: 'internal_error' });
  }
};
const updateProfileById = async (req, res) => {
  try {
    const { user_id, username, bio } = req.body;
    const id = Number(user_id);
    if (!id) return res.status(400).json({ message: 'ต้องมี user_id' });

    // ถ้าผู้ใช้กรอก username ใหม่ ต้องเช็คซ้ำซ้อน
    if (username && String(username).trim() !== '') {
      const dupe = await pool.query(
        'SELECT 1 FROM public.users WHERE LOWER(username)=LOWER($1) AND id_user<>$2',
        [String(username).trim(), id]
      );
      if (dupe.rowCount > 0) {
        return res.status(409).json({ message: 'Username นี้ถูกใช้แล้ว' });
      }
    }

    await pool.query(
      `UPDATE public.users
         SET username = COALESCE($2, username),
             bio      = COALESCE($3, bio)
       WHERE id_user = $1`,
      [id, (username ?? null), (bio ?? null)]
    );

    return res.json({ message: 'อัปเดตโปรไฟล์สำเร็จ' });
  } catch (err) {
    console.error('updateProfileById error:', err);
    return res.status(500).json({ message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
};

// อัปโหลด avatar ด้วย user_id (ไม่ต้องใช้ email)
const uploadAvatarById = async (req, res) => {
  try {
    const id = Number(req.body.user_id);
    if (!id) return res.status(400).json({ message: 'ต้องมี user_id' });
    if (!req.file) return res.status(400).json({ message: 'ไม่พบไฟล์รูป (avatar)' });

    const fileUrl = `/uploads/avatars/${req.file.filename}`;
    await pool.query(
      'UPDATE public.users SET avatar_url=$2 WHERE id_user=$1',
      [id, fileUrl]
    );

    return res.json({ message: 'อัปโหลดรูปสำเร็จ', avatar_url: fileUrl });
  } catch (err) {
    console.error('uploadAvatarById error:', err);
    return res.status(500).json({ message: 'อัปโหลดรูปไม่สำเร็จ' });
  }
};

module.exports = { startRegister, verifyRegister, resendOtp, login, updateProfile, uploadAvatar, getUserBrief, updateProfileById, uploadAvatarById };
