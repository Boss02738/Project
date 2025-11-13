const Tesseract = require('tesseract.js');
const fs = require('fs');

/**
 * ตรวจสอบสลิปธนาคารอัตโนมัติ
 * - อ่านจำนวนเงินจากสลิป
 * - ตรวจสอบว่าสัดส่วนกับจำนวนที่ต้องชำระ
 */

async function extractTextFromImage(imagePath) {
  try {
    const { data } = await Tesseract.recognize(imagePath, 'tha+eng');
    return data.text || '';
  } catch (error) {
    console.error('OCR error:', error.message);
    throw new Error('failed_to_read_slip');
  }
}

function parseSlipAmount(ocrText) {
  // ตรวจหาจำนวนเงินที่อาจเป็นรูปแบบต่าง ๆ
  const patterns = [
    /จำนวนเงิน[:\s]+([0-9,]+\.?[0-9]*)/i,
    /amount[:\s]+([0-9,]+\.?[0-9]*)/i,
    /([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?)\s*(?:บาท|thb|฿)/i,
    /([0-9]{1,3}(?:\.[0-9]{2})?)\s*(?:บาท|thb|฿)/i,
  ];

  for (const pattern of patterns) {
    const match = ocrText.match(pattern);
    if (match && match[1]) {
      const amountStr = match[1].replace(/,/g, '');
      const amount = parseFloat(amountStr);
      if (!isNaN(amount) && amount > 0) {
        return amount;
      }
    }
  }

  return null;
}

function parseDateFromSlip(ocrText) {
  const datePatterns = [
    /(\d{1,2}\/\d{1,2}\/\d{4})/,
    /(\d{1,2}-\d{1,2}-\d{4})/,
    /(\d{4}-\d{1,2}-\d{1,2})/,
  ];

  for (const pattern of datePatterns) {
    const match = ocrText.match(pattern);
    if (match) {
      return match[1];
    }
  }
  return null;
}

/**
 * ตรวจสอบสลิปแบบพื้นฐาน
 * @param {string} imagePath - เส้นทางไฟล์ภาพสลิป
 * @param {number} expectedAmountBaht - จำนวนเงินที่ต้องชำระ (บาท)
 * @param {number} tolerancePercent - ช่วงความเผื่อ (%) เช่น 10 = ±10%
 * @returns {object} { verified: boolean, amount: number, date: string, ocrText: string, error?: string }
 */
async function verifySlip(imagePath, expectedAmountBaht, tolerancePercent = 10) {
  try {
    if (!fs.existsSync(imagePath)) {
      return { verified: false, error: 'file_not_found' };
    }

    const stats = fs.statSync(imagePath);
    if (stats.size > 25 * 1024 * 1024) {
      return { verified: false, error: 'file_too_large' };
    }

    const ocrText = await extractTextFromImage(imagePath);
    
    if (!ocrText || ocrText.trim().length === 0) {
      return { verified: false, error: 'cannot_read_slip', ocrText: '' };
    }

    const extractedAmount = parseSlipAmount(ocrText);
    
    if (extractedAmount === null) {
      return {
        verified: false,
        error: 'amount_not_found',
        ocrText: ocrText.substring(0, 500),
      };
    }

    const minAcceptable = expectedAmountBaht * (1 - tolerancePercent / 100);
    const maxAcceptable = expectedAmountBaht * (1 + tolerancePercent / 100);
    const isAmountValid = extractedAmount >= minAcceptable && extractedAmount <= maxAcceptable;

    if (!isAmountValid) {
      return {
        verified: false,
        amount: extractedAmount,
        expected: expectedAmountBaht,
        error: 'amount_mismatch',
        ocrText: ocrText.substring(0, 500),
      };
    }

    const transferDate = parseDateFromSlip(ocrText);

    return {
      verified: true,
      amount: extractedAmount,
      date: transferDate || 'unknown',
      ocrText: ocrText.substring(0, 500),
    };
  } catch (error) {
    console.error('verifySlip error:', error);
    return {
      verified: false,
      error: error.message || 'verification_error',
    };
  }
}

module.exports = {
  verifySlip,
  extractTextFromImage,
  parseSlipAmount,
  parseDateFromSlip,
};
