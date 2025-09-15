const bcrypt = require('bcrypt');
const pool = require('../models/db');
const { genOTP } = require('../utils/otp');
const { sendOTP } = require('../utils/mailer');

const OTP_EXPIRE_MIN = Number(process.env.OTP_EXPIRE_MIN || 5);
const RESEND_COOLDOWN = Number(process.env.OTP_RESEND_COOLDOWN_SEC || 60);

// helper ตรวจ email ว่าต้องลงท้ายด้วย @ku.th
function isValidKuEmail(email) {
  return /^[^@]+@ku\.th$/.test(email);
}

// 🔹 Step 1: Request OTP
const startRegister = async (req, res) => {
  const { username, email, password } = req.body;
  if (!username || !email || !password)
    return res.status(400).json({ message: 'กรอก username, email, password ให้ครบ' });

  // email ต้องเป็น @ku.th
  if (!isValidKuEmail(email)) {
    return res.status(400).json({ message: 'อนุญาตเฉพาะอีเมล @ku.th เท่านั้น' });
  }

  try {
    // กัน username/email ซ้ำตั้งแต่แรก
    const dupeUser = await pool.query('SELECT 1 FROM public.users WHERE username=$1', [username]);
    if (dupeUser.rowCount > 0) return res.status(409).json({ message: 'Username นี้ถูกใช้แล้ว' });

    const dupeEmail = await pool.query('SELECT 1 FROM public.users WHERE email=$1', [email]);
    if (dupeEmail.rowCount > 0) return res.status(409).json({ message: 'อีเมลนี้ถูกใช้แล้ว' });

    // คูลดาวน์ OTP
    const last = await pool.query(`
      SELECT created_at FROM public.verification_password
      WHERE email=$1 AND purpose='register'
      ORDER BY created_at DESC LIMIT 1`, [email]);

    if (last.rowCount > 0) {
      const diff = (Date.now() - new Date(last.rows[0].created_at).getTime()) / 1000;
      if (diff < RESEND_COOLDOWN) {
        return res.status(429).json({
          message: `ขอ OTP ได้อีกใน ${Math.ceil(RESEND_COOLDOWN - diff)} วิ`,
          retry_after_sec: Math.ceil(RESEND_COOLDOWN - diff)
        });
      }
    }

    const otp = genOTP(6);
    const now = new Date();
    const expiresAt = new Date(now.getTime() + OTP_EXPIRE_MIN * 60 * 1000);

    // ลบ OTP เก่า (กันใช้ได้หลายตัว)
    await pool.query(`DELETE FROM public.verification_password WHERE email=$1 AND purpose='register'`, [email]);

    await pool.query(`
      INSERT INTO public.verification_password(email, otp, purpose, expires_at)
      VALUES ($1,$2,'register',$3)`, [email, otp, expiresAt]);

    await sendOTP(email, otp, OTP_EXPIRE_MIN);

    res.json({
      message: 'ส่ง OTP แล้ว กรุณาตรวจอีเมล',
      email,
      ttl_min: OTP_EXPIRE_MIN,
      now: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      resend_after_sec: RESEND_COOLDOWN,
    });
  } catch (err) {
    console.error('startRegister error:', err);
    res.status(500).json({ message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
};

// 🔹 Step 2: Verify OTP & Register
const verifyRegister = async (req, res) => {
  const { username, email, password, otp } = req.body;
  if (!username || !email || !password || !otp)
    return res.status(400).json({ message: 'กรอกข้อมูลให้ครบ' });

  if (!isValidKuEmail(email)) {
    return res.status(400).json({ message: 'อนุญาตเฉพาะอีเมล @ku.th เท่านั้น' });
  }

  try {
    const q = await pool.query(`
      SELECT id, expires_at FROM public.verification_password
      WHERE email=$1 AND otp=$2 AND purpose='register'
      ORDER BY created_at DESC LIMIT 1`, [email, otp]);

    if (q.rowCount === 0) return res.status(400).json({ message: 'OTP ไม่ถูกต้อง' });
    if (new Date(q.rows[0].expires_at).getTime() < Date.now())
      return res.status(400).json({ message: 'OTP หมดอายุแล้ว' });

    // กันซ้ำอีกชั้น
    const dupeUser = await pool.query('SELECT 1 FROM public.users WHERE username=$1', [username]);
    if (dupeUser.rowCount > 0) return res.status(409).json({ message: 'Username นี้ถูกใช้แล้ว' });

    const dupeEmail = await pool.query('SELECT 1 FROM public.users WHERE email=$1', [email]);
    if (dupeEmail.rowCount > 0) return res.status(409).json({ message: 'อีเมลนี้ถูกใช้แล้ว' });

    // สมัครจริง
    const hash = await bcrypt.hash(password, 10);
    await pool.query(`
      INSERT INTO public.users(username, password, email, email_verified)
      VALUES ($1,$2,$3,true)`, [username, hash, email]);

    // ลบ OTP หลังใช้
    await pool.query('DELETE FROM public.verification_password WHERE id=$1', [q.rows[0].id]);
    res.json({ message: 'สมัครสำเร็จ' });
  } catch (err) {
    console.error('verifyRegister error:', err);
    res.status(500).json({ message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
};

// 🔹 Step 3: Resend OTP
const resendOtp = async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ message: 'ต้องใส่ email' });

  if (!isValidKuEmail(email)) {
    return res.status(400).json({ message: 'อนุญาตเฉพาะอีเมล @ku.th เท่านั้น' });
  }

  try {
    const u = await pool.query('SELECT 1 FROM public.users WHERE email=$1', [email]);
    if (u.rowCount > 0) return res.status(409).json({ message: 'อีเมลนี้สมัครแล้ว' });

    const last = await pool.query(`
      SELECT created_at FROM public.verification_password
      WHERE email=$1 AND purpose='register'
      ORDER BY created_at DESC LIMIT 1`, [email]);

    if (last.rowCount > 0) {
      const diff = (Date.now() - new Date(last.rows[0].created_at).getTime()) / 1000;
      if (diff < RESEND_COOLDOWN) {
        return res.status(429).json({
          message: `ขอ OTP ได้อีกใน ${Math.ceil(RESEND_COOLDOWN - diff)} วิ`,
          retry_after_sec: Math.ceil(RESEND_COOLDOWN - diff)
        });
      }
    }

    const otp = genOTP(6);
    const now = new Date();
    const expiresAt = new Date(now.getTime() + OTP_EXPIRE_MIN * 60 * 1000);

    // ลบ OTP เก่าทั้งหมดก่อน
    await pool.query(`DELETE FROM public.verification_password WHERE email=$1 AND purpose='register'`, [email]);

    await pool.query(`
      INSERT INTO public.verification_password(email, otp, purpose, expires_at)
      VALUES ($1,$2,'register',$3)`, [email, otp, expiresAt]);

    await sendOTP(email, otp, OTP_EXPIRE_MIN);

    res.json({
      message: 'ส่ง OTP ใหม่แล้ว',
      email,
      ttl_min: OTP_EXPIRE_MIN,
      now: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      resend_after_sec: RESEND_COOLDOWN,
    });
  } catch (err) {
    console.error('resendOtp error:', err);
    res.status(500).json({ message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
};

const login = async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password)
    return res.status(400).json({ message: 'กรอกอีเมลและรหัสผ่าน' });

  try {
    const result = await pool.query('SELECT * FROM public.users WHERE email=$1', [email]);
    if (result.rowCount === 0)
      return res.status(401).json({ message: 'ไม่พบบัญชีนี้' });

    const user = result.rows[0];

    // ต้อง verify email ก่อน
    if (!user.email_verified) {
      return res.status(403).json({ message: 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ' });
    }

    const match = await bcrypt.compare(password, user.password);
    if (!match)
      return res.status(401).json({ message: 'รหัสผ่านไม่ถูกต้อง' });

    // สำเร็จ
    res.json({
      message: 'เข้าสู่ระบบสำเร็จ',
      user: {
        id: user.id_user,
        username: user.username,
        email: user.email,
      },
    });
  } catch (err) {
    console.error('login error:', err);
    res.status(500).json({ message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
};


module.exports = { startRegister, verifyRegister, resendOtp, login };
