function genOTP(digits = 6) {
  let s = '';
  for (let i = 0; i < digits; i++) {
    s += Math.floor(Math.random() * 10);
  }
  return s;
}

module.exports = { genOTP };
