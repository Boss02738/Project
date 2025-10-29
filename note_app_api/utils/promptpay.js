// utils/promptpay.js
// NOTE: นี่เป็น payload แบบง่าย (stub) ให้ระบบทำงานได้ก่อน
// ภายหลังอยากได้ EMVCo จริงๆ ค่อยเปลี่ยนให้คำนวณ CRC-16 ฯลฯ
function generatePromptPayPayload(mobile, amountBahtStr) {
  // เก็บเบอร์แบบ 0812345678 และจำนวนเงินเป็น string 2 ตำแหน่ง (เช่น '29.00')
  return `PROMPTPAY|MOBILE:${mobile}|AMOUNT:${amountBahtStr}`;
}

module.exports = { generatePromptPayPayload };
