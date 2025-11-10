const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: process.env.MAIL_HOST,
  port: Number(process.env.MAIL_PORT || 587),
  secure: String(process.env.MAIL_SECURE).toLowerCase() === 'true',
  auth: {
    user: process.env.MAIL_USER,
    pass: process.env.MAIL_PASS,
  },
});

async function sendOTP(to, otp, minutes = 5) {
  return transporter.sendMail({
    from: process.env.MAIL_FROM,
    to,
    subject: `รหัสยืนยัน OTP (หมดอายุใน ${minutes} นาที)`,
    html: `
      <div style="font-family:Segoe UI,Arial">
        <h2>ยืนยันอีเมลสำหรับสมัครสมาชิก</h2>
        <p>รหัส OTP ของคุณคือ:</p>
        <p style="font-size:24px;letter-spacing:2px"><b>${otp}</b></p>
        <p>กรุณานำรหัสนี้ไปกรอกในหน้าแอปเพื่อยืนยันบัญชีของคุณ</p>
        <p>รหัสจะหมดอายุใน ${minutes} นาที</p>
      </div>
    `,
  });
}

async function sendOTP_ResetPassword(to, otp, minutes = 5) {
  return transporter.sendMail({
    from: process.env.MAIL_FROM,
    to,
    subject: `OTP สำหรับรีเซ็ตรหัสผ่าน (หมดอายุใน ${minutes} นาที)`,
    html: `
      <div style="font-family:Segoe UI,Arial">
        <h2>คำขอรีเซ็ตรหัสผ่าน</h2>
        <p>คุณได้รับอีเมลนี้เพราะมีการร้องขอให้รีเซ็ตรหัสผ่านบัญชีของคุณ</p>
        <p>รหัส OTP สำหรับยืนยันตัวตนคือ:</p>
        <p style="font-size:24px;letter-spacing:2px"><b>${otp}</b></p>
        <p>รหัสนี้จะหมดอายุใน ${minutes} นาที</p>
        <p>หากคุณไม่ได้ร้องขอรีเซ็ตรหัสผ่าน โปรดเพิกเฉยต่ออีเมลนี้</p>
      </div>
    `,
  });
}

module.exports = { sendOTP, sendOTP_ResetPassword };
