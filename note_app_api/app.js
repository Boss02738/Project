// Project/note_app_api/app.js  (COMBINED: API หลัก + NoteCoLab realtime + Pricing/Payments)

/* ================= CORE & THIRD-PARTY ================= */
require("dotenv").config();
const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const cors = require("cors");
const bodyParser = require("body-parser");
const multer = require("multer");
const path = require("path");
const bcrypt = require("bcrypt");
const crypto = require("crypto");
const dayjs = require("dayjs");
const QRCode = require("qrcode");
const session = require("express-session");
const expressLayouts = require("express-ejs-layouts");

/* ================= DB ================= */
const pool = require("./models/db");

/* ================= ROUTES (ของระบบ) ================= */
const authRoutes = require("./routes/authRoutes");
const postRoutes = require("./routes/postRoutes");
const searchRoutes = require("./routes/searchRoutes");
const adminRoutes = require("./routes/admin"); // [FIX] router นี้มี path เริ่มด้วย /admin อยู่แล้ว
const userRoutes = require("./routes/user");
const walletRouter = require("./routes/wallet");
const withdrawalsRouter = require("./routes/withdrawals");
const purchasesRouter = require("./routes/purchases");
const reportRoutes = require("./routes/reportRoutes");
const notificationRoutes = require("./routes/notificationRoutes");
const friendRoutes = require("./routes/friendRoutes");
/* ================= APP/HTTP/IO ================= */
const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*", methods: ["GET", "POST"] },
});

/* ================= MIDDLEWARE ================= */
app.use(cors());
app.use((req, _res, next) => {
  // [FIX] ย้าย logger ไว้ก่อน routes
  console.log(req.method, req.originalUrl);
  next();
});
app.set('io', io);
app.set("view engine", "ejs");
app.set("views", path.join(process.cwd(), "views"));
app.use(express.json({ limit: "50mb" }));
app.use(bodyParser.urlencoded({ extended: true, limit: "50mb" }));
app.use("/uploads", express.static(path.join(__dirname, "uploads")));
app.use(
  session({
    secret: process.env.SESSION_SECRET || "devsecret",
    resave: false,
    saveUninitialized: false,
  })
);
app.use(express.urlencoded({ extended: true }));
app.use(expressLayouts);
app.set("layout", "layouts/main");
app.use("/api/reports", reportRoutes);

/* ================= MULTER (สลิป/ไฟล์อัปโหลด) ================= */
const storage = multer.diskStorage({
  destination: function (_req, _file, cb) {
    cb(null, path.join(__dirname, "uploads/"));
  },
  filename: function (_req, file, cb) {
    const fileExt = path.extname(file.originalname);
    const fileBase = path.basename(file.originalname, fileExt);
    const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1e9);
    cb(null, fileBase + "-" + uniqueSuffix + fileExt);
  },
});
const upload = multer({ storage });

/* ================= ROUTES MOUNT ================= */
// API prefix
app.use("/api/auth", authRoutes);
app.use("/api/posts", postRoutes);
app.use("/api/search", searchRoutes);
app.use("/api", userRoutes);
app.use(withdrawalsRouter);
app.use(walletRouter);
app.use(purchasesRouter);
app.use("/api/friends", friendRoutes);
app.use("/api/notifications", notificationRoutes);
app.use(adminRoutes);

/* ================= HEALTH ================= */
app.get("/", (_req, res) =>
  res.send("NoteCoLab server ok (merged in note_app_api)")
);

/* ===================================================================
   SCHEMA HELPERS (NoteCoLab + Pricing/Payments)
   =================================================================== */
async function ensureSchema3Tables() {
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
      snapshot   JSONB NOT NULL DEFAULT '{"lines":[],"texts":[],"images":[]}'::jsonb,
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
      owner_id INTEGER,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    ALTER TABLE boards      ADD COLUMN IF NOT EXISTS password_hash TEXT;
    ALTER TABLE boards      ADD COLUMN IF NOT EXISTS name          TEXT;
    ALTER TABLE boards      ADD COLUMN IF NOT EXISTS created_at    TIMESTAMPTZ DEFAULT now();
    ALTER TABLE boards      ADD COLUMN IF NOT EXISTS updated_at    TIMESTAMPTZ DEFAULT now();

    ALTER TABLE board_pages ADD COLUMN IF NOT EXISTS snapshot   JSONB   DEFAULT '{"lines":[],"texts":[],"images":[]}'::jsonb;
    ALTER TABLE board_pages ALTER COLUMN snapshot SET DEFAULT '{"lines":[],"texts":[],"images":[]}'::jsonb;
    ALTER TABLE board_pages ADD COLUMN IF NOT EXISTS version    BIGINT  DEFAULT 1;
    ALTER TABLE board_pages ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS title      TEXT;
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS board_id   TEXT;
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS owner_id   INTEGER;
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS cover_png  TEXT;
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
    ALTER TABLE documents   ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_board_pages_updated       ON board_pages(board_id, updated_at DESC);
    CREATE INDEX IF NOT EXISTS idx_documents_updated         ON documents(updated_at DESC);
    CREATE INDEX IF NOT EXISTS idx_documents_owner_updated   ON documents(owner_id, updated_at DESC);
  `);
}

// [FIX] ให้ schema ด้าน “ซื้อโพสต์” ใช้ INT อ้างอิง posts(id) / users(id_user)
async function ensurePricingPaymentsSchema() {
  // users.phone (สำหรับ PromptPay)
  await pool.query(
    `ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);`
  );

  // posts ราคา
  await pool.query(`
    ALTER TABLE public.posts
    ADD COLUMN IF NOT EXISTS price_type VARCHAR(10) NOT NULL DEFAULT 'free',
    ADD COLUMN IF NOT EXISTS price_amount_satang INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS price_currency VARCHAR(3) NOT NULL DEFAULT 'THB';
  `);

  // purchases / payment_slips / post_access / purchased_posts เป็น INT FK
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.purchases (
      id SERIAL PRIMARY KEY,
      post_id INT NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
      buyer_id INT NOT NULL REFERENCES public.users(id_user) ON DELETE CASCADE,
      seller_id INT NOT NULL REFERENCES public.users(id_user) ON DELETE CASCADE,
      amount_satang INT NOT NULL,
      currency VARCHAR(3) NOT NULL DEFAULT 'THB',
      status VARCHAR(16) NOT NULL DEFAULT 'pending', -- pending|slip_uploaded|approved|rejected|expired|paid
      qr_payload TEXT,
      expires_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS public.payment_slips (
      id SERIAL PRIMARY KEY,
      purchase_id INT NOT NULL REFERENCES public.purchases(id) ON DELETE CASCADE,
      file_path TEXT NOT NULL,
      uploaded_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS public.post_access (
      id SERIAL PRIMARY KEY,
      post_id INT NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
      user_id INT NOT NULL REFERENCES public.users(id_user) ON DELETE CASCADE,
      granted_at TIMESTAMPTZ DEFAULT now(),
      UNIQUE (post_id, user_id)
    );

    CREATE TABLE IF NOT EXISTS public.purchased_posts (
      post_id INT NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
      user_id INT NOT NULL REFERENCES public.users(id_user) ON DELETE CASCADE,
      granted_at TIMESTAMPTZ DEFAULT now(),
      PRIMARY KEY (post_id, user_id)
    );
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_purchases_status_created ON public.purchases(status, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_post_access_user ON public.post_access(user_id, granted_at DESC);
    CREATE INDEX IF NOT EXISTS idx_purchased_posts_user ON public.purchased_posts(user_id, granted_at DESC);
  `);
}

/* ===================================================================
   HELPERS (NoteCoLab)
   =================================================================== */
function slugify(name) {
  const s = String(name || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return s ? (s.length <= 64 ? s : s.slice(0, 64)) : `room_${Date.now()}`;
}
function cleanB64(s) {
  if (typeof s !== "string") return s;
  return s.replace(/^data:image\/[^;]+;base64,/, "");
}
function normInt(x) {
  const n = parseInt(x, 10);
  return Number.isFinite(n) ? n : null;
}

async function upsertBoard({ id, name, password }) {
  const rounds = parseInt(process.env.BCRYPT_ROUNDS || "10", 10);
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
       SET snapshot='{"lines":[],"texts":[],"images":[]}'::jsonb,
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
  if (count <= 1) return { ok: false, reason: "only_one_page" };
  if (pageIndex < 0 || pageIndex > count - 1)
    return { ok: false, reason: "out_of_range" };

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `DELETE FROM board_pages WHERE board_id=$1 AND page_index=$2`,
      [boardId, pageIndex]
    );
    await client.query(
      `UPDATE board_pages SET page_index = page_index - 1 WHERE board_id=$1 AND page_index > $2`,
      [boardId, pageIndex]
    );
    await client.query("COMMIT");
    return { ok: true };
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

/* ===================================================================
   REST: NoteCoLab (rooms/documents)
   =================================================================== */
app.post("/rooms", async (req, res) => {
  try {
    const { roomId, name, password } = req.body || {};
    const id = (roomId && `${roomId}`.trim()) || slugify(name || "");
    await upsertBoard({ id, name, password });
    await ensurePageExists(id, 0);
    res.json({ ok: true, roomId: id, name: name || null });
  } catch (e) {
    console.error("POST /rooms", e);
    res.status(500).json({ error: "internal_error" });
  }
});

app.get("/documents", async (req, res) => {
  try {
    const userId = req.query.user_id ? Number(req.query.user_id) : null;
    if (userId != null && !Number.isInteger(userId))
      return res.status(400).json({ error: "invalid_user_id" });

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
    console.error("GET /documents", e);
    res.status(500).json({ error: "internal_error" });
  }
});

app.get("/documents/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { rows } = await pool.query(
      `SELECT id, title, board_id, pages, cover_png, updated_at, created_at
         FROM documents WHERE id=$1`,
      [id]
    );
    if (!rows[0]) return res.status(404).json({ error: "not_found" });
    res.json(rows[0]);
  } catch (e) {
    console.error("GET /documents/:id", e);
    res.status(500).json({ error: "internal_error" });
  }
});

app.post("/documents", async (req, res) => {
  try {
    const body = req.body || {};
    const id = body.id;
    const title = body.title;
    const boardIdRaw = body.boardId ?? body.board_id ?? null;
    const coverRaw = body.coverPng ?? body.cover_png ?? null;
    const owner_id = body.owner_id ?? body.ownerId ?? null;
    const pages = body.pages;

    if (!Array.isArray(pages))
      return res.status(400).json({ error: "pages_required" });

    const pagesClean = pages.map((p) => {
      const idx = Number.isFinite(+p.index) ? +p.index : 0;
      const data = p.data && typeof p.data === "object" ? p.data : {};
      const lines = Array.isArray(data.lines) ? data.lines : [];
      const texts = Array.isArray(data.texts) ? data.texts : [];
      const images = Array.isArray(data.images) ? data.images : [];
      const imagesClean = images.map((im) => ({
        ...im,
        bytesB64: cleanB64(im.bytesB64),
      }));
      return { index: idx, data: { lines, texts, images: imagesClean } };
    });

    const boardVal =
      typeof boardIdRaw === "string" &&
      boardIdRaw.trim().toLowerCase() === "offline"
        ? null
        : typeof boardIdRaw === "string"
        ? boardIdRaw.trim()
        : null;

    if (boardVal) {
      try {
        await upsertBoard({ id: boardVal, name: null, password: null });
        await ensurePageExists(boardVal, 0);
      } catch (e) {
        console.error("ensure board failed", e);
      }
    }

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
      [
        docId,
        title || "Untitled",
        boardVal,
        JSON.stringify(pagesClean),
        cleanB64(coverRaw) || null,
        normInt(owner_id) || null,
      ]
    );
    res.json({ ok: true, id: docId });
  } catch (e) {
    console.error("POST /documents", e);
    res.status(500).json({ error: "internal_error" });
  }
});

app.delete("/documents/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.query.user_id ? Number(req.query.user_id) : null;
    if (userId != null && !Number.isInteger(userId))
      return res.status(400).json({ error: "invalid_user_id" });

    if (userId != null) {
      const r = await pool.query(
        `DELETE FROM documents WHERE id=$1 AND owner_id=$2`,
        [id, userId]
      );
      if (r.rowCount === 0)
        return res.status(404).json({ error: "not_found_or_not_owner" });
      return res.json({ ok: true });
    }

    await pool.query(`DELETE FROM documents WHERE id=$1`, [id]);
    res.json({ ok: true });
  } catch (e) {
    console.error("DELETE /documents/:id", e);
    res.status(500).json({ error: "internal_error" });
  }
});

/* ===================================================================
   USERS (เพิ่ม phone สำหรับ PromptPay)
   =================================================================== */
app.post("/api/users/:id/profile", async (req, res) => {
  try {
    const { id } = req.params;
    const { bio, phone } = req.body;
    await pool.query(
      `UPDATE public.users
         SET bio = COALESCE($1,bio),
             phone = COALESCE($2,phone)
       WHERE id_user = $3`, // [FIX] users.id_user
      [bio ?? null, phone ?? null, id]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error("POST /api/users/:id/profile", e);
    res.status(500).json({ error: "internal_error" });
  }
});

/* ===================================================================
   PROMPTPAY HELPERS
   =================================================================== */
function normalizeThaiPhone(phone) {
  let p = (phone || "").replace(/\D/g, "");
  if (p.startsWith("0")) p = "66" + p.slice(1);
  return p;
}
function crc16(payload) {
  let crc = 0xffff;
  for (let i = 0; i < payload.length; i++) {
    crc ^= payload.charCodeAt(i) << 8;
    for (let j = 0; j < 8; j++) {
      if (crc & 0x8000) crc = (crc << 1) ^ 0x1021;
      else crc <<= 1;
      crc &= 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, "0");
}
function generatePromptPayPayload(phoneOrID, amountBaht) {
  const target = normalizeThaiPhone(phoneOrID);
  const merchantAccInfo =
    "0016A000000677010111" +
    "02" +
    String(target.length).padStart(2, "0") +
    target;
  const merchantInfo =
    "29" + String(merchantAccInfo.length).padStart(2, "0") + merchantAccInfo;
  const amountStr =
    typeof amountBaht === "number" ? amountBaht.toFixed(2) : null;

  let payload = "";
  payload += "00" + "02" + "01";
  payload += "01" + "02" + "11";
  payload += merchantInfo;
  payload += "53" + "03" + "764";
  if (amountStr)
    payload += "54" + String(amountStr.length).padStart(2, "0") + amountStr;
  payload += "58" + "02" + "TH";
  payload += "59" + "02" + "NA";
  payload += "60" + "02" + "TH";
  payload += "63" + "04";
  const crc = crc16(payload);
  payload += crc;
  return payload;
}

/* ===================================================================
   PAYMENTS FLOW (ปรับเป็นสคีมา INT)
   =================================================================== */

// เริ่มคำสั่งซื้อ → สร้าง PromptPay QR (หมดอายุ 10 นาที)
app.post("/api/purchases", async (req, res) => {
  try {
    const { postId, buyerId } = req.body;

    // [FIX] posts.user_id → users.id_user
    const pr = await pool.query(
      `SELECT p.id, p.user_id AS seller_id, p.price_type, p.price_amount_satang,
              u.phone AS seller_phone
         FROM public.posts p
         JOIN public.users u ON u.id_user = p.user_id
        WHERE p.id = $1`,
      [postId]
    );
    if (!pr.rowCount) return res.status(404).json({ error: "post_not_found" });

    const post = pr.rows[0];
    if (post.price_type !== "paid")
      return res.status(400).json({ error: "post_is_free" });
    if (!post.seller_phone)
      return res.status(400).json({ error: "seller_no_phone" });

    const amountBaht = post.price_amount_satang / 100.0;
    const payload = generatePromptPayPayload(post.seller_phone, amountBaht);
    const expiresAt = dayjs().add(10, "minute").toISOString();

    const ins = await pool.query(
      `INSERT INTO public.purchases
         (post_id, buyer_id, seller_id, amount_satang, currency, status, qr_payload, expires_at)
       VALUES ($1,$2,$3,$4,'THB','pending',$5,$6)
       RETURNING *`,
      [
        postId,
        buyerId,
        post.seller_id,
        post.price_amount_satang,
        payload,
        expiresAt,
      ]
    );

    const qrPngDataUrl = await QRCode.toDataURL(payload);
    res.json({ purchase: ins.rows[0], qrPngDataUrl });
  } catch (e) {
    console.error("POST /api/purchases", e);
    res.status(500).json({ error: "internal_error" });
  }
});

// เช็คสถานะ + จัดการหมดอายุ
app.get("/api/purchases/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const r = await pool.query(`SELECT * FROM public.purchases WHERE id = $1`, [
      id,
    ]);
    if (!r.rowCount) return res.status(404).json({ error: "not_found" });

    const purchase = r.rows[0];
    if (
      purchase.status === "pending" &&
      purchase.expires_at &&
      dayjs().isAfter(purchase.expires_at)
    ) {
      const up = await pool.query(
        `UPDATE public.purchases SET status='expired' WHERE id=$1 RETURNING *`,
        [id]
      );
      return res.json({ purchase: up.rows[0] });
    }
    res.json({ purchase });
  } catch (e) {
    console.error("GET /api/purchases/:id", e);
    res.status(500).json({ error: "internal_error" });
  }
});

// อัปโหลดสลิป
app.post("/api/purchases/:id/slip", upload.single("slip"), async (req, res) => {
  try {
    const { id } = req.params;
    if (!req.file) return res.status(400).json({ error: "missing_slip_file" });

    const pr = await pool.query(`SELECT * FROM public.purchases WHERE id=$1`, [
      id,
    ]);
    if (!pr.rowCount)
      return res.status(404).json({ error: "purchase_not_found" });
    if (pr.rows[0].status === "expired")
      return res.status(400).json({ error: "purchase_expired" });

    await pool.query(
      `INSERT INTO public.payment_slips (purchase_id, file_path) VALUES ($1,$2)`,
      [
        id,
        "/" + path.relative(process.cwd(), req.file.path).replace(/\\/g, "/"),
      ]
    );
    const up = await pool.query(
      `UPDATE public.purchases SET status='slip_uploaded' WHERE id=$1 RETURNING *`,
      [id]
    );
    res.json({ purchase: up.rows[0] });
  } catch (e) {
    console.error("POST /api/purchases/:id/slip", e);
    res.status(500).json({ error: "internal_error" });
  }
});

/* (OPTIONAL) API สำหรับแอดมินตรวจสลิปแบบ JSON */
app.get("/api/admin/pending-slips", async (_req, res) => {
  try {
    const r = await pool.query(`
      SELECT pu.*, ps.file_path,
             p.text AS post_text,
             ub.username AS buyer_name, us.username AS seller_name
        FROM public.purchases pu
        JOIN public.posts p  ON p.id = pu.post_id
        JOIN public.users ub ON ub.id_user = pu.buyer_id
        JOIN public.users us ON us.id_user = pu.seller_id
   LEFT JOIN public.payment_slips ps ON ps.purchase_id = pu.id
       WHERE pu.status = 'slip_uploaded'
       ORDER BY pu.created_at DESC
    `);
    res.json({ items: r.rows });
  } catch (e) {
    console.error("GET /api/admin/pending-slips", e);
    res.status(500).json({ error: "internal_error" });
  }
});

/* ===================================================================
   Socket.IO: NoteCoLab
   =================================================================== */
io.on("connection", (socket) => {
  socket.on("join", async ({ boardId, password }) => {
    try {
      const board = await getBoard(boardId);
      if (!board)
        return socket.emit("join_error", { message: "Room not found" });

      if (board.password_hash) {
        const hasPwd = typeof password === "string" && password.length > 0;
        if (!hasPwd)
          return socket.emit("join_error", {
            message: "Password required",
            needPassword: true,
          });
        const ok = await bcrypt.compare(password ?? "", board.password_hash);
        if (!ok)
          return socket.emit("join_error", {
            message: "Invalid password",
            needPassword: true,
          });
      }

      socket.join(boardId);
      socket.emit("join_ok", { boardId });
      await ensurePageExists(boardId, 0);
    } catch (e) {
      console.error("join error", e);
      socket.emit("join_error", { message: "Join failed" });
    }
  });

  socket.on("init_page", async ({ boardId, page }) => {
    try {
      const p = Number.isInteger(page) ? page : 0;
      await ensurePageExists(boardId, p);
      const snap = await getSnapshot(boardId, p);
      socket.emit("init_data", {
        snapshot: snap ? { data: snap.snapshot, version: snap.version } : null,
        strokes: [],
        events: [],
        page: p,
      });
    } catch (e) {
      console.error("init_page error", e);
      socket.emit("init_data", {
        snapshot: null,
        strokes: [],
        events: [],
        page: page ?? 0,
      });
    }
  });

  socket.on("get_pages_meta", async ({ boardId }) => {
    try {
      const count = await getPageCount(boardId);
      socket.emit("pages_meta", { count: count > 0 ? count : 1 });
    } catch (e) {
      console.error("get_pages_meta error", e);
      socket.emit("pages_meta", { count: 1 });
    }
  });

  socket.on("add_page", async ({ boardId, page }) => {
    try {
      if (!socket.rooms.has(boardId)) return;
      const p = Number.isInteger(page) ? page : 0;
      await ensurePageExists(boardId, p);
      const count = await getPageCount(boardId);
      io.to(boardId).emit("pages_meta", { count });
    } catch (e) {
      console.error("add_page error", e);
    }
  });

  socket.on("delete_page", async ({ boardId, page }) => {
    try {
      if (!socket.rooms.has(boardId)) return;
      const p = Number.isInteger(page) ? page : 0;
      const result = await deletePageAndReindex(boardId, p);
      io.to(boardId).emit("page_deleted", { deletedPage: p });
      const count = await getPageCount(boardId);
      io.to(boardId).emit("pages_meta", { count });
      socket.emit("delete_page_result", {
        ok: result.ok,
        reason: result.reason ?? null,
      });
    } catch (e) {
      console.error("delete_page error", e);
      socket.emit("delete_page_result", { ok: false, reason: "server_error" });
    }
  });

  socket.on("set_sketch", async ({ boardId, page, sketch }) => {
    try {
      if (!socket.rooms.has(boardId)) return;
      const p = Number.isInteger(page) ? page : 0;

      const payload =
        sketch && typeof sketch === "object"
          ? {
              lines: Array.isArray(sketch.lines) ? sketch.lines : [],
              texts: Array.isArray(sketch.texts) ? sketch.texts : [],
              images: Array.isArray(sketch.images) ? sketch.images : [],
            }
          : { lines: [], texts: [], images: [] };

      await setPageSnapshot(boardId, p, payload);
      socket.to(boardId).emit("set_sketch", { sketch: payload, page: p });
    } catch (e) {
      console.error("set_sketch error", e);
    }
  });

  socket.on("clear_board", async ({ boardId, page }) => {
    try {
      if (!socket.rooms.has(boardId)) return;
      const p = Number.isInteger(page) ? page : 0;
      await clearPage(boardId, p);
      socket.to(boardId).emit("clear_board", { page: p });
    } catch (e) {
      console.error("clear_board error", e);
    }
  });
  socket.on("register", (userId) => {
    const id = Number(userId);
    if (id > 0) socket.join(`user:${id}`);
  });
});

/* ===================================================================
   START
   =================================================================== */
const PORT = process.env.PORT || 3000;
server.listen(PORT, async () => {
  try {
    await ensureSchema3Tables();
    await ensurePricingPaymentsSchema();
    console.log(`🚀 Server running on http://localhost:${PORT}`);
  } catch (e) {
    console.error("Failed to ensure schema:", e);
    process.exit(1);
  }
});