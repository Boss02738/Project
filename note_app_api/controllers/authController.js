const bcrypt = require("bcrypt");
const pool = require("../models/db");
const { genOTP } = require("../utils/otp");
const { sendOTP, sendOTP_ResetPassword } = require("../utils/mailer");

const OTP_EXPIRE_MIN = Number(process.env.OTP_EXPIRE_MIN || 5);
const RESEND_COOLDOWN = Number(process.env.OTP_RESEND_COOLDOWN_SEC || 60);

function isValidKuEmail(email) {
  return /^[^@]+@ku\.th$/.test(email);
}

const startRegister = async (req, res) => {
  const { username, email, password } = req.body;
  if (!username || !email || !password)
    return res
      .status(400)
      .json({ message: "กรอก username, email, password ให้ครบ" });

  if (!isValidKuEmail(email)) {
    return res
      .status(400)
      .json({ message: "อนุญาตเฉพาะอีเมล @ku.th เท่านั้น" });
  }

  try {
    const dupeUser = await pool.query(
      "SELECT 1 FROM public.users WHERE username=$1",
      [username]
    );
    if (dupeUser.rowCount > 0)
      return res.status(409).json({ message: "Username นี้ถูกใช้แล้ว" });

    const dupeEmail = await pool.query(
      "SELECT 1 FROM public.users WHERE email=$1",
      [email]
    );
    if (dupeEmail.rowCount > 0)
      return res.status(409).json({ message: "อีเมลนี้ถูกใช้แล้ว" });

    const last = await pool.query(
      `
      SELECT created_at FROM public.verification_password
      WHERE email=$1 AND purpose='register'
      ORDER BY created_at DESC LIMIT 1`,
      [email]
    );

    if (last.rowCount > 0) {
      const diff =
        (Date.now() - new Date(last.rows[0].created_at).getTime()) / 1000;
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

    await pool.query(
      `DELETE FROM public.verification_password WHERE email=$1 AND purpose='register'`,
      [email]
    );

    await pool.query(
      `
      INSERT INTO public.verification_password(email, otp, purpose, expires_at)
      VALUES ($1,$2,'register',$3)`,
      [email, otp, expiresAt]
    );

    await sendOTP(email, otp, OTP_EXPIRE_MIN);

    res.json({
      message: "ส่ง OTP แล้ว กรุณาตรวจอีเมล",
      email,
      ttl_min: OTP_EXPIRE_MIN,
      now: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      resend_after_sec: RESEND_COOLDOWN,
    });
  } catch (err) {
    console.error("startRegister error:", err);
    res.status(500).json({ message: "เกิดข้อผิดพลาดภายในระบบ" });
  }
};

const verifyRegister = async (req, res) => {
  const { username, email, password, otp } = req.body;
  if (!username || !email || !password || !otp)
    return res.status(400).json({ message: "กรอกข้อมูลให้ครบ" });

  if (!isValidKuEmail(email)) {
    return res
      .status(400)
      .json({ message: "อนุญาตเฉพาะอีเมล @ku.th เท่านั้น" });
  }

  try {
    const q = await pool.query(
      `
      SELECT id, expires_at FROM public.verification_password
      WHERE email=$1 AND otp=$2 AND purpose='register'
      ORDER BY created_at DESC LIMIT 1`,
      [email, otp]
    );

    if (q.rowCount === 0)
      return res.status(400).json({ message: "OTP ไม่ถูกต้อง" });
    if (new Date(q.rows[0].expires_at).getTime() < Date.now())
      return res.status(400).json({ message: "OTP หมดอายุแล้ว" });

    const dupeUser = await pool.query(
      "SELECT 1 FROM public.users WHERE username=$1",
      [username]
    );
    if (dupeUser.rowCount > 0)
      return res.status(409).json({ message: "Username นี้ถูกใช้แล้ว" });

    const dupeEmail = await pool.query(
      "SELECT 1 FROM public.users WHERE email=$1",
      [email]
    );
    if (dupeEmail.rowCount > 0)
      return res.status(409).json({ message: "อีเมลนี้ถูกใช้แล้ว" });

    const hash = await bcrypt.hash(password, 10);
    await pool.query(
      `
      INSERT INTO public.users(username, password, email, email_verified, profile_completed)
      VALUES ($1,$2,$3,true,false)`,
      [username, hash, email]
    );

    await pool.query("DELETE FROM public.verification_password WHERE id=$1", [
      q.rows[0].id,
    ]);
    res.json({ message: "สมัครสำเร็จ" });
  } catch (err) {
    console.error("verifyRegister error:", err);
    res.status(500).json({ message: "เกิดข้อผิดพลาดภายในระบบ" });
  }
};

const resendOtp = async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ message: "ต้องใส่ email" });

  if (!isValidKuEmail(email)) {
    return res
      .status(400)
      .json({ message: "อนุญาตเฉพาะอีเมล @ku.th เท่านั้น" });
  }

  try {
    const u = await pool.query("SELECT 1 FROM public.users WHERE email=$1", [
      email,
    ]);
    if (u.rowCount > 0)
      return res.status(409).json({ message: "อีเมลนี้สมัครแล้ว" });

    const last = await pool.query(
      `
      SELECT created_at FROM public.verification_password
      WHERE email=$1 AND purpose='register'
      ORDER BY created_at DESC LIMIT 1`,
      [email]
    );

    if (last.rowCount > 0) {
      const diff =
        (Date.now() - new Date(last.rows[0].created_at).getTime()) / 1000;
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

    await pool.query(
      `DELETE FROM public.verification_password WHERE email=$1 AND purpose='register'`,
      [email]
    );

    await pool.query(
      `
      INSERT INTO public.verification_password(email, otp, purpose, expires_at)
      VALUES ($1,$2,'register',$3)`,
      [email, otp, expiresAt]
    );

    await sendOTP(email, otp, OTP_EXPIRE_MIN);

    res.json({
      message: "ส่ง OTP ใหม่แล้ว",
      email,
      ttl_min: OTP_EXPIRE_MIN,
      now: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      resend_after_sec: RESEND_COOLDOWN,
    });
  } catch (err) {
    console.error("resendOtp error:", err);
    res.status(500).json({ message: "เกิดข้อผิดพลาดภายในระบบ" });
  }
};

const login = async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password)
    return res.status(400).json({ message: "กรอกอีเมลและรหัสผ่าน" });

  try {
    const r = await pool.query("SELECT * FROM public.users WHERE email=$1", [
      email,
    ]);
    if (r.rowCount === 0)
      return res.status(401).json({ message: "ไม่พบบัญชีนี้" });

    const u = r.rows[0];
    if (!u.email_verified)
      return res.status(403).json({ message: "กรุณายืนยันอีเมลก่อน" });

    const ok = await bcrypt.compare(password, u.password);
    if (!ok) return res.status(401).json({ message: "รหัสผ่านไม่ถูกต้อง" });

    const needProfile =
      u.profile_completed !== undefined
        ? !u.profile_completed
        : !u.bio || !u.gender;

    const avatarUrl =
      u.avatar_url && u.avatar_url.trim() !== ""
        ? u.avatar_url
        : "/uploads/avatars/default.png";

    return res.json({
      message: "เข้าสู่ระบบสำเร็จ",
      user: {
        id: u.id_user,
        username: u.username,
        email: u.email,
        avatar_url: avatarUrl,
      },
      needProfile,
    });
  } catch (err) {
    console.error("login error:", err);
    res.status(500).json({ message: "เกิดข้อผิดพลาดภายในระบบ" });
  }
};

const updateProfile = async (req, res) => {
  const { email, bio, gender } = req.body;
  if (!email) return res.status(400).json({ message: "ต้องมี email" });

  const allow = new Set(["male", "female", "other"]);
  if (gender && !allow.has(String(gender).toLowerCase())) {
    return res.status(400).json({ message: "ค่า gender ไม่ถูกต้อง" });
  }

  try {
    const user = await pool.query(
      "SELECT id_user FROM public.users WHERE email=$1",
      [email]
    );
    if (user.rowCount === 0)
      return res.status(404).json({ message: "ไม่พบบัญชีนี้" });

    await pool.query(
      `UPDATE public.users
         SET bio=$2,
             gender=$3,
             profile_completed=true
       WHERE email=$1`,
      [email, bio ?? null, (gender ?? "").toLowerCase() || null]
    );

    res.json({ message: "อัปเดตโปรไฟล์สำเร็จ" });
  } catch (err) {
    console.error("updateProfile error:", err);
    res.status(500).json({ message: "เกิดข้อผิดพลาดภายในระบบ" });
  }
};

const uploadAvatar = async (req, res) => {
  try {
    const email = req.body.email;
    if (!email)
      return res.status(400).json({ message: "ต้องส่ง email มาด้วย" });
    if (!req.file)
      return res.status(400).json({ message: "ไม่พบไฟล์รูป (avatar)" });

    const u = await pool.query(
      "SELECT id_user FROM public.users WHERE email=$1",
      [email]
    );
    if (u.rowCount === 0)
      return res.status(404).json({ message: "ไม่พบบัญชีนี้" });

    const fileUrl = `/uploads/avatars/${req.file.filename}`;

    await pool.query("UPDATE public.users SET avatar_url=$2 WHERE email=$1", [
      email,
      fileUrl,
    ]);

    console.log("[uploadAvatar] saved:", email, fileUrl);
    return res.json({ message: "อัปโหลดรูปสำเร็จ", avatar_url: fileUrl });
  } catch (err) {
    console.error("uploadAvatar error:", err);
    return res.status(500).json({ message: "อัปโหลดรูปไม่สำเร็จ" });
  }
};

const getUserBrief = async (req, res) => {
  try {
    const { id } = req.params;

    const q = `
      SELECT
    u.id_user,
    u.username,
    u.email,
    COALESCE(u.bio, '') AS bio,
    COALESCE(u.gender, '') AS gender,
    COALESCE(u.avatar_url, '/uploads/avatars/default.png') AS avatar_url,
    COALESCE(u.profile_completed, false) AS profile_completed,
    (SELECT COUNT(*)::int FROM public.posts p WHERE p.user_id = u.id_user) AS post_count,
    (
      SELECT COUNT(*)::int
      FROM public.friend_edges fe
      WHERE fe.status = 'accepted'
        AND (fe.user_a = u.id_user OR fe.user_b = u.id_user)
    ) AS friends_count
  FROM public.users u
  WHERE u.id_user = $1
  LIMIT 1
`;
    const r = await pool.query(q, [id]);
    if (r.rowCount === 0)
      return res.status(404).json({ message: "user not found" });

    const row = r.rows[0];
    if (row.friends_count === undefined) row.friends_count = 0;

    return res.json(row);
  } catch (err) {
    console.error("getUserBrief error:", err);
    return res.status(500).json({ message: "server error" });
  }
};
const updateProfileById = async (req, res) => {
  try {
    const { user_id, username, bio } = req.body;
    const id = Number(user_id);
    if (!id) return res.status(400).json({ message: "ต้องมี user_id" });

    if (username && String(username).trim() !== "") {
      const dupe = await pool.query(
        "SELECT 1 FROM public.users WHERE LOWER(username)=LOWER($1) AND id_user<>$2",
        [String(username).trim(), id]
      );
      if (dupe.rowCount > 0) {
        return res.status(409).json({ message: "Username นี้ถูกใช้แล้ว" });
      }
    }

    await pool.query(
      `UPDATE public.users
         SET username = COALESCE($2, username),
             bio      = COALESCE($3, bio)
       WHERE id_user = $1`,
      [id, username ?? null, bio ?? null]
    );

    return res.json({ message: "อัปเดตโปรไฟล์สำเร็จ" });
  } catch (err) {
    console.error("updateProfileById error:", err);
    return res.status(500).json({ message: "เกิดข้อผิดพลาดภายในระบบ" });
  }
};

const uploadAvatarById = async (req, res) => {
  try {
    const id = Number(req.body.user_id);
    if (!id) return res.status(400).json({ message: "ต้องมี user_id" });
    if (!req.file)
      return res.status(400).json({ message: "ไม่พบไฟล์รูป (avatar)" });

    const fileUrl = `/uploads/avatars/${req.file.filename}`;
    await pool.query("UPDATE public.users SET avatar_url=$2 WHERE id_user=$1", [
      id,
      fileUrl,
    ]);

    return res.json({ message: "อัปโหลดรูปสำเร็จ", avatar_url: fileUrl });
  } catch (err) {
    console.error("uploadAvatarById error:", err);
    return res.status(500).json({ message: "อัปโหลดรูปไม่สำเร็จ" });
  }
};
const startResetPassword = async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ message: "ต้องใส่ email" });
    if (!isValidKuEmail(email)) {
      return res
        .status(400)
        .json({ message: "อนุญาตเฉพาะอีเมล @ku.th เท่านั้น" });
    }

    const u = await pool.query(
      "SELECT id_user FROM public.users WHERE email=$1",
      [email]
    );
    if (u.rowCount === 0)
      return res.status(404).json({ message: "ไม่พบบัญชีนี้" });

    const last = await pool.query(
      `
      SELECT created_at FROM public.verification_password
      WHERE email=$1 AND purpose='reset'
      ORDER BY created_at DESC LIMIT 1`,
      [email]
    );
    if (last.rowCount > 0) {
      const diff =
        (Date.now() - new Date(last.rows[0].created_at).getTime()) / 1000;
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

    await pool.query(
      `DELETE FROM public.verification_password WHERE email=$1 AND purpose='reset'`,
      [email]
    );
    await pool.query(
      `
      INSERT INTO public.verification_password(email, otp, purpose, expires_at)
      VALUES ($1,$2,'reset',$3)`,
      [email, otp, expiresAt]
    );

    await sendOTP_ResetPassword(email, otp, OTP_EXPIRE_MIN);
    return res.json({
      message: "ส่ง OTP สำหรับรีเซ็ตรหัสผ่านแล้ว",
      email,
      ttl_min: OTP_EXPIRE_MIN,
      resend_after_sec: RESEND_COOLDOWN,
    });
  } catch (err) {
    console.error("startResetPassword error:", err);
    return res.status(500).json({ message: "เกิดข้อผิดพลาดภายในระบบ" });
  }
};

const resetPassword = async (req, res) => {
  try {
    const { email, otp, new_password } = req.body;
    if (!email || !otp || !new_password) {
      return res
        .status(400)
        .json({ message: "กรอก email, otp, new_password ให้ครบ" });
    }
    if (!isValidKuEmail(email)) {
      return res
        .status(400)
        .json({ message: "อนุญาตเฉพาะอีเมล @ku.th เท่านั้น" });
    }
    if (String(otp).length !== 6) {
      return res.status(400).json({ message: "OTP ไม่ถูกต้อง" });
    }

    const q = await pool.query(
      `
      SELECT id, expires_at FROM public.verification_password
      WHERE email=$1 AND otp=$2 AND purpose='reset'
      ORDER BY created_at DESC LIMIT 1`,
      [email, otp]
    );
    if (q.rowCount === 0)
      return res.status(400).json({ message: "OTP ไม่ถูกต้อง" });
    if (new Date(q.rows[0].expires_at).getTime() < Date.now()) {
      return res.status(400).json({ message: "OTP หมดอายุแล้ว" });
    }

    const hash = await bcrypt.hash(new_password, 10);
    const u = await pool.query(
      "UPDATE public.users SET password=$2 WHERE email=$1 RETURNING id_user",
      [email, hash]
    );
    if (u.rowCount === 0)
      return res.status(404).json({ message: "ไม่พบบัญชีนี้" });

    await pool.query("DELETE FROM public.verification_password WHERE id=$1", [
      q.rows[0].id,
    ]);

    return res.json({ message: "รีเซ็ตรหัสผ่านสำเร็จ" });
  } catch (err) {
    console.error("resetPassword error:", err);
    return res.status(500).json({ message: "เกิดข้อผิดพลาดภายในระบบ" });
  }
};
const changePassword = async (req, res) => {
  try {
    const { user_id, old_password, new_password } = req.body;
    const user = await pool.query(
      "SELECT password FROM users WHERE id_user=$1",
      [user_id]
    );
    if (!user.rows.length)
      return res.status(404).json({ message: "ไม่พบบัญชีผู้ใช้" });

    const valid = await bcrypt.compare(old_password, user.rows[0].password);
    if (!valid)
      return res.status(400).json({ message: "รหัสผ่านเดิมไม่ถูกต้อง" });

    const newHash = await bcrypt.hash(new_password, 10);
    await pool.query("UPDATE users SET password=$1 WHERE id_user=$2", [
      newHash,
      user_id,
    ]);
    res.json({ message: "เปลี่ยนรหัสผ่านสำเร็จ" });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "เกิดข้อผิดพลาดภายในเซิร์ฟเวอร์" });
  }
};

module.exports = {
  startRegister,
  verifyRegister,
  resendOtp,
  login,
  updateProfile,
  uploadAvatar,
  getUserBrief,
  updateProfileById,
  uploadAvatarById,
  startResetPassword,
  resetPassword,
  changePassword,
};
