// controllers/authController.js
const pool = require('../models/db');
const bcrypt = require('bcrypt');

exports.register = async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ message: 'กรอกไม่ครบถ้วน' });

  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    const result = await pool.query(
      'INSERT INTO users (username, password) VALUES ($1, $2) RETURNING id_user, username',
      [username, hashedPassword]
    );
    res.status(201).json({ message: 'ลงทะเบียนสำเร็จ', user: result.rows[0] });
  } catch (err) {
    console.error(err);
    if (err.code === '23505') {
      res.status(400).json({ message: 'Username นี้มีอยู่แล้ว' });
    } else {
      res.status(500).json({ message: 'เกิดข้อผิดพลาดในเซิร์ฟเวอร์' });
    }
  }
};

exports.login = async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ message: 'กรอกไม่ครบ' });

  try {
    const result = await pool.query('SELECT * FROM users WHERE username = $1', [username]);
    const user = result.rows[0];
    if (!user) return res.status(401).json({ message: 'ผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' });

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) return res.status(401).json({ message: 'ผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' });

    res.status(200).json({ message: 'เข้าสู่ระบบสำเร็จ', user: { id: user.id, username: user.username } });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'เกิดข้อผิดพลาดในเซิร์ฟเวอร์' });
  }
};

// เพิ่มฟังก์ชันสำหรับดึง users ทั้งหมด
exports.getAllUsers = async (req, res) => {
  try {
    const result = await pool.query('SELECT id_user, username FROM users');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด', error: err.message });
  }
};