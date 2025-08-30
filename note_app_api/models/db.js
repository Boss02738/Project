// const { Pool } = require('pg');
// //แก้ตรงนี้ db_name กับ password 
// const pool = new Pool({
//   user: 'postgres',
//   host: 'localhost',
//   database: 'note_app',
//   password: 'Bossboss_02738',  // เปลี่ยนเป็นรหัสของคุณ
//   port: 5432,
// });

// module.exports = pool;
// models/db.js
require('dotenv').config();
const { Pool } = require('pg');

// สร้าง Pool สำหรับเชื่อมต่อ PostgreSQL
const pool = new Pool({
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
});

module.exports = pool;
