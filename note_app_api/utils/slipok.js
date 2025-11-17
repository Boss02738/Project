// utils/slipok.js
const axios = require('axios');
const fs = require('fs');
const FormData = require('form-data');

/**
 * ตรวจสลิปด้วย SlipOK
 * @param {string} filePath path ของไฟล์สลิปบนเซิร์ฟเวอร์
 * @param {number} amountBaht จำนวนเงินที่คาดหวัง (หน่วยบาท)
 * @returns {Promise<{verified:boolean, amount:number, raw:any, code?:number, message?:string}>}
 */
async function verifyWithSlipOK(filePath, amountBaht) {
  const branchId = process.env.SLIPOK_BRANCH_ID || '';
  const apiKey   = process.env.SLIPOK_API_KEY || '';
  if (!branchId || !apiKey) {
    throw new Error('Missing SLIPOK_BRANCH_ID or SLIPOK_API_KEY');
  }

  const url = `https://api.slipok.com/api/line/apikey/${branchId}`;

  const form = new FormData();
  form.append('files', fs.createReadStream(filePath));
  form.append('log', 'true');
  if (amountBaht && Number.isFinite(amountBaht)) {
    form.append('amount', String(Number(amountBaht)));
  }

  try {
    console.log('[SlipOK REQUEST]', { url, amountBaht });

    const res = await axios.post(url, form, {
      headers: {
        'x-authorization': apiKey,
        ...form.getHeaders(),
      },
      timeout: 15000,
      validateStatus: () => true,
    });

    console.log('[SlipOK RESPONSE]', res.status, JSON.stringify(res.data));

    // สำเร็จ: HTTP 200 + มี data
    if (res.status === 200 && res.data?.data) {
      const data = res.data.data;
      const amt = Number(data.amount ?? data.paidLocalAmount ?? 0);
      return { verified: true, amount: amt, raw: data };
    }

    // ไม่ผ่าน
    const code = res.data?.code;
    const message = res.data?.message || 'Slip verify failed';
    return { verified: false, amount: 0, raw: res.data, code, message };
  } catch (err) {
    console.error('[SlipOK ERROR]', err.message);
    return { verified: false, amount: 0, raw: null, message: err.message };
  }
}

module.exports = { verifyWithSlipOK };
