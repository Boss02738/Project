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
        <p>รหัส OTP ของคุณ:</p>
        <p style="font-size:24px;letter-spacing:2px"><b>${otp}</b></p>
        <p>รหัสจะหมดอายุใน ${minutes} นาที</p>
      </div>
    `,
  });
}

module.exports = { sendOTP };
