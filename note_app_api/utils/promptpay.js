const promptpay = require('promptpay-qr');

function generatePromptPayPayload({ target, amount }) {
  const payload = promptpay(target, amount ? { amount } : undefined);
  return payload;
}

module.exports = { generatePromptPayPayload };
