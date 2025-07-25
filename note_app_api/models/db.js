const { Pool } = require('pg');

const pool = new Pool({
  user: 'postgres',
  host: 'localhost',
  database: 'note_app',
  password: 'Bossboss_02738',  // เปลี่ยนเป็นรหัสของคุณ
  port: 5432,
});

module.exports = pool;
