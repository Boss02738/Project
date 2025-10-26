// Project/note_app_api/app.js  (COMBINED: API หลัก + NoteCoLab realtime)

// ====== CORE & THIRD-PARTY ======
require('dotenv').config();
const express = require('express');
const http = require('http');                  // <— NEW
const { Server } = require('socket.io');       // <— NEW
const cors = require('cors');
const bodyParser = require('body-parser');
const multer = require('multer');
const path = require('path');
const bcrypt = require('bcrypt');              // <— NEW
const crypto = require('crypto');              // <— NEW

// ====== DB POOL (ใช้ของโปรเจกต์เดิม) ======
const pool = require('./models/db');           // ใช้ env: DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME

// ====== ROUTES ของระบบเดิม ======
const authRoutes = require('./routes/authRoutes');
const postRoutes = require('./routes/postRoutes');
const searchRoutes = require('./routes/searchRoutes');

// ====== APP/HTTP SERVER/IO ======
const app = express();
const server = http.createServer(app);         // <— ใช้ server.listen ด้านล่าง
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});

// ====== MIDDLEWARE ======
app.use(cors());
app.use(express.json({ limit: '15mb' }));      // แทน bodyParser.json
app.use(bodyParser.urlencoded({ extended: true, limit: '15mb' }));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// ====== MULTER (จากโค้ดเดิม) ======
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, path.join(__dirname, 'uploads/'));
  },
  filename: function (req, file, cb) {
    const fileExt = path.extname(file.originalname);
    const fileBase = path.basename(file.originalname, fileExt);
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, fileBase + '-' + uniqueSuffix + fileExt);
  },
});
const upload = multer({ storage });

// ====== ROUTES เดิม (คง prefix /api/*) ======
app.use('/api/auth', authRoutes);
app.use('/api/posts', (req, res, next) => {
  // inject multer ในเส้น post สร้างโพสต์ ถ้าจำเป็น
  // ใช้ตามที่คุณมีใน postRoutes หรือจะคงไว้เฉพาะใน postRoutes ก็ได้
  next();
}, postRoutes);
app.use('/api/search', searchRoutes);

// ========== HEALTH ==========
app.get('/', (_req, res) => res.send('NoteCoLab server ok (merged in note_app_api)'));

/* ===================================================================
   SCHEMA & HELPERS (NoteCoLab): ใช้ DB ของโปรเจกต์เดิม (pool)
   ตาราง: boards, board_pages, documents
   =================================================================== */

async function ensureSchema3Tables() {
  // 1) create tables (ถ้ายังไม่มี)
  await pool.query(`
    CREATE TABLE IF NOT EXISTS boards (
      id TEXT PRIMARY KEY,
      password_hash TEXT,
      name TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS board_pages (
      board_id   TEXT NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
      page_index INT  NOT NULL,
      snapshot   JSONB NOT NULL DEFAULT '{"lines":[],"texts":[]}'::jsonb,
      version    BIGINT NOT NULL DEFAULT 1,
      updated_at TIMESTAMPTZ DEFAULT now(),
      PRIMARY KEY (board_id, page_index)
    );

    CREATE TABLE IF NOT EXISTS documents (
      id TEXT PRIMARY KEY,
      title TEXT,
      board_id TEXT,
      pages JSONB NOT NULL,
      cover_png TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  // 2) add missing columns (กันโค้ดเก่า)
  await pool.query(`
    ALTER TABLE boards      ADD COLUMN IF NOT EXISTS password_hash TEXT;
    ALTER TABLE boards      ADD COLUMN IF NOT EXISTS name          TEXT;
    ALTER TABLE boards      ADD COLUMN IF NOT EXISTS created_at    TIMESTAMPTZ DEFAULT now();
    ALTER TABLE boards      ADD COLUMN IF NOT EXISTS updated_at    TIMESTAMPTZ DEFAULT now();

    ALTER TABLE board_pages ADD COLUMN IF NOT EXISTS snapshot   JSONB   DEFAULT '{"lines":[],"texts":[]}'::jsonb;
    ALTER TABLE board_pages ADD COLUMN IF NOT EXISTS version    BIGINT  DEFAULT 1;
    ALTER TABLE board_pages ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS title      TEXT;
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS board_id   TEXT;
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS owner_id   INTEGER;
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS cover_png  TEXT;
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
  `);

  // 3) indexes
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_board_pages_updated ON board_pages(board_id, updated_at DESC);
    CREATE INDEX IF NOT EXISTS idx_documents_updated   ON documents(updated_at DESC);
    CREATE INDEX IF NOT EXISTS idx_documents_owner_updated ON documents(owner_id, updated_at DESC);
  `);
}

function slugify(name) {
  const s = String(name || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return s ? (s.length <= 64 ? s : s.slice(0, 64)) : `room_${Date.now()}`;
}

async function upsertBoard({ id, name, password }) {
  const rounds = parseInt(process.env.BCRYPT_ROUNDS || '10', 10);
  const hash = password ? await bcrypt.hash(password, rounds) : null;

  if (hash) {
    await pool.query(
      `INSERT INTO boards (id, name, password_hash)
       VALUES ($1,$2,$3)
       ON CONFLICT (id) DO UPDATE
         SET name = EXCLUDED.name,
             password_hash = EXCLUDED.password_hash,
             updated_at = now()`,
      [id, name || null, hash]
    );
  } else {
    await pool.query(
      `INSERT INTO boards (id, name)
       VALUES ($1,$2)
       ON CONFLICT (id) DO UPDATE
         SET name = COALESCE(EXCLUDED.name, boards.name),
             updated_at = now()`,
      [id, name || null]
    );
  }
}

async function getBoard(id) {
  const { rows } = await pool.query(
    `SELECT id, name, password_hash FROM boards WHERE id=$1`,
    [id]
  );
  return rows[0] || null;
}

async function getPageCount(boardId) {
  const { rows } = await pool.query(
    `SELECT COALESCE(MAX(page_index),-1) AS max_page FROM board_pages WHERE board_id=$1`,
    [boardId]
  );
  const max = Number(rows[0]?.max_page ?? -1);
  return max + 1;
}

async function ensurePageExists(boardId, pageIndex) {
  await pool.query(
    `INSERT INTO board_pages (board_id, page_index)
     VALUES ($1,$2)
     ON CONFLICT (board_id, page_index) DO NOTHING`,
    [boardId, pageIndex]
  );
}

async function setPageSnapshot(boardId, pageIndex, snapshotJson) {
  await ensurePageExists(boardId, pageIndex);
  await pool.query(
    `UPDATE board_pages
       SET snapshot=$3, version = version + 1, updated_at = now()
     WHERE board_id=$1 AND page_index=$2`,
    [boardId, pageIndex, snapshotJson]
  );
}

async function clearPage(boardId, pageIndex) {
  await ensurePageExists(boardId, pageIndex);
  await pool.query(
    `UPDATE board_pages
       SET snapshot='{"lines":[],"texts":[]}'::jsonb,
           version = version + 1,
           updated_at = now()
     WHERE board_id=$1 AND page_index=$2`,
    [boardId, pageIndex]
  );
}

async function getSnapshot(boardId, pageIndex) {
  const { rows } = await pool.query(
    `SELECT snapshot, version FROM board_pages WHERE board_id=$1 AND page_index=$2`,
    [boardId, pageIndex]
  );
  return rows[0] || null;
}

async function deletePageAndReindex(boardId, pageIndex) {
  const count = await getPageCount(boardId);
  if (count <= 1) return { ok: false, reason: 'only_one_page' };
  if (pageIndex < 0 || pageIndex > count - 1) return { ok: false, reason: 'out_of_range' };

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `DELETE FROM board_pages WHERE board_id=$1 AND page_index=$2`,
      [boardId, pageIndex]
    );
    await client.query(
      `UPDATE board_pages SET page_index = page_index - 1
       WHERE board_id=$1 AND page_index > $2`,
      [boardId, pageIndex]
    );
    await client.query('COMMIT');
    return { ok: true };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

/* ====================== REST: NoteCoLab ====================== */

// สร้าง/อัปเดตห้อง (รองรับ password)
app.post('/rooms', async (req, res) => {
  try {
    const { roomId, name, password } = req.body || {};
    const id = (roomId && `${roomId}`.trim()) || slugify(name || '');
    await upsertBoard({ id, name, password });
    await ensurePageExists(id, 0); // เตรียมหน้าแรก
    res.json({ ok: true, roomId: id, name: name || null });
  } catch (e) {
    console.error('POST /rooms', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

// รายการเอกสาร (รองรับ ?user_id= to filter per-user)
app.get('/documents', async (req, res) => {
  try {
    const userId = req.query.user_id ? Number(req.query.user_id) : null;
    if (userId != null && !Number.isInteger(userId)) return res.status(400).json({ error: 'invalid_user_id' });

    let q;
    if (userId != null) {
      q = await pool.query(
        `SELECT id, title, board_id, cover_png, updated_at
           FROM documents
          WHERE owner_id = $1
          ORDER BY updated_at DESC
          LIMIT 200`,
        [userId]
      );
    } else {
      q = await pool.query(
        `SELECT id, title, board_id, cover_png, updated_at
           FROM documents
          ORDER BY updated_at DESC
          LIMIT 200`
      );
    }
    res.json(q.rows);
  } catch (e) {
    console.error('GET /documents', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

// อ่านเอกสาร
app.get('/documents/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { rows } = await pool.query(
      `SELECT id, title, board_id, pages, cover_png, updated_at, created_at
         FROM documents WHERE id=$1`,
      [id]
    );
    if (!rows[0]) return res.status(404).json({ error: 'not_found' });
    res.json(rows[0]);
  } catch (e) {
    console.error('GET /documents/:id', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

// สร้าง/อัปเดตเอกสาร
app.post('/documents', async (req, res) => {
  try {
    const { id, title, boardId, pages, coverPng, owner_id } = req.body || {};
    if (!Array.isArray(pages)) return res.status(400).json({ error: 'pages_required' });

    const docId = id || crypto.randomUUID();
    await pool.query(
      `INSERT INTO documents (id, title, board_id, pages, cover_png, owner_id)
       VALUES ($1,$2,$3,$4::jsonb,$5,$6)
       ON CONFLICT (id) DO UPDATE SET
         title=EXCLUDED.title,
         board_id=EXCLUDED.board_id,
         pages=EXCLUDED.pages,
         cover_png=COALESCE(EXCLUDED.cover_png, documents.cover_png),
         owner_id=COALESCE(EXCLUDED.owner_id, documents.owner_id),
         updated_at=now()`,
      [docId, title || 'Untitled', boardId || null, JSON.stringify(pages), coverPng || null, owner_id || null]
    );
    res.json({ ok: true, id: docId });
  } catch (e) {
    console.error('POST /documents', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

// ลบเอกสาร
// Delete document — optionally require owner match via ?user_id=
app.delete('/documents/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.query.user_id ? Number(req.query.user_id) : null;
    if (userId != null && !Number.isInteger(userId)) return res.status(400).json({ error: 'invalid_user_id' });

    if (userId != null) {
      const r = await pool.query(`DELETE FROM documents WHERE id=$1 AND owner_id=$2`, [id, userId]);
      if (r.rowCount === 0) return res.status(404).json({ error: 'not_found_or_not_owner' });
      return res.json({ ok: true });
    }

    await pool.query(`DELETE FROM documents WHERE id=$1`, [id]);
    res.json({ ok: true });
  } catch (e) {
    console.error('DELETE /documents/:id', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

/* ====================== Socket.IO: NoteCoLab ====================== */

io.on('connection', (socket) => {
  socket.on('join', async ({ boardId, password }) => {
    try {
      const board = await getBoard(boardId);
      if (!board) return socket.emit('join_error', { message: 'Room not found' });

      if (board.password_hash) {
        const hasPwd = typeof password === 'string' && password.length > 0;
        if (!hasPwd) {
          return socket.emit('join_error', { message: 'Password required', needPassword: true });
        }
        const ok = await bcrypt.compare(password ?? '', board.password_hash);
        if (!ok) return socket.emit('join_error', { message: 'Invalid password', needPassword: true });
      }

      socket.join(boardId);
      socket.emit('join_ok', { boardId });
      await ensurePageExists(boardId, 0);
    } catch (e) {
      console.error('join error', e);
      socket.emit('join_error', { message: 'Join failed' });
    }
  });

  socket.on('init_page', async ({ boardId, page }) => {
    try {
      const p = Number.isInteger(page) ? page : 0;
      await ensurePageExists(boardId, p);
      const snap = await getSnapshot(boardId, p);
      socket.emit('init_data', {
        snapshot: snap ? { data: snap.snapshot, version: snap.version } : null,
        strokes: [],
        events: [],
        page: p,
      });
    } catch (e) {
      console.error('init_page error', e);
      socket.emit('init_data', { snapshot: null, strokes: [], events: [], page: page ?? 0 });
    }
  });

  socket.on('get_pages_meta', async ({ boardId }) => {
    try {
      const count = await getPageCount(boardId);
      socket.emit('pages_meta', { count: count > 0 ? count : 1 });
    } catch (e) {
      console.error('get_pages_meta error', e);
      socket.emit('pages_meta', { count: 1 });
    }
  });

  socket.on('add_page', async ({ boardId, page }) => {
    try {
      if (!socket.rooms.has(boardId)) return;
      const p = Number.isInteger(page) ? page : 0;
      await ensurePageExists(boardId, p);
      const count = await getPageCount(boardId);
      io.to(boardId).emit('pages_meta', { count });
    } catch (e) {
      console.error('add_page error', e);
    }
  });

  socket.on('delete_page', async ({ boardId, page }) => {
    try {
      if (!socket.rooms.has(boardId)) return;
      const p = Number.isInteger(page) ? page : 0;
      const result = await deletePageAndReindex(boardId, p);
      io.to(boardId).emit('page_deleted', { deletedPage: p });
      const count = await getPageCount(boardId);
      io.to(boardId).emit('pages_meta', { count });
      socket.emit('delete_page_result', { ok: result.ok, reason: result.reason ?? null });
    } catch (e) {
      console.error('delete_page error', e);
      socket.emit('delete_page_result', { ok: false, reason: 'server_error' });
    }
  });

  socket.on('set_sketch', async ({ boardId, page, sketch }) => {
    try {
      if (!socket.rooms.has(boardId)) return;
      const p = Number.isInteger(page) ? page : 0;

      const payload =
        sketch && typeof sketch === 'object'
          ? {
              lines: Array.isArray(sketch.lines) ? sketch.lines : [],
              texts: Array.isArray(sketch.texts) ? sketch.texts : [],
            }
          : { lines: [], texts: [] };

      await setPageSnapshot(boardId, p, payload);
      socket.to(boardId).emit('set_sketch', { sketch: payload, page: p });
    } catch (e) {
      console.error('set_sketch error', e);
    }
  });

  socket.on('clear_board', async ({ boardId, page }) => {
    try {
      if (!socket.rooms.has(boardId)) return;
      const p = Number.isInteger(page) ? page : 0;
      await clearPage(boardId, p);
      socket.to(boardId).emit('clear_board', { page: p });
    } catch (e) {
      console.error('clear_board error', e);
    }
  });
});

/* ====================== START ====================== */

const PORT = process.env.PORT || 3000;

server.listen(PORT, async () => {
  try {
    await ensureSchema3Tables();
    console.log(`🚀 Server running on http://localhost:${PORT}`);
  } catch (e) {
    console.error('Failed to ensure schema:', e);
    process.exit(1);
  }
});
