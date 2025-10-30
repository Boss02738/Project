// utils/promptpay.js
const promptpay = require('promptpay-qr');

/**
 * target: เบอร์มือถือ (เช่น '0812345678') หรือ เลขบัตรปชช./นิติบุคคล
 * amount: จำนวนเงิน (number) ไม่ใส่ก็ได้ (จะเป็น QR แบบไม่ fix amount)
 */
function generatePromptPayPayload({ target, amount }) {
  // ไลบรารีจะจัดรูปแบบ + คำนวณ CRC16 ให้ครบ
  const payload = promptpay(target, amount ? { amount } : undefined);
  return payload;
}

module.exports = { generatePromptPayPayload };
