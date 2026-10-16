// Tests and managed runtimes can supply configuration directly without opening .env.
if (process.env.LOAD_DOTENV !== "false") require("dotenv").config();
const express = require("express");
const session = require("express-session");
const pgSession = require("connect-pg-simple")(session);
const path = require("path");
const pool = require("./db");

const authRoutes = require("./routes/auth");
const resources = require("./routes/resources");
const reportsRoutes = require("./routes/reports");
const productRoutes = require("./routes/products");
const { requireAuth } = require("./middleware/auth");
const { requirePermission } = require("./middleware/permissions");

const isProduction = process.env.NODE_ENV === "production";
const sessionSecret = process.env.SESSION_SECRET;
if (!sessionSecret) {
  if (isProduction) {
    console.error("[config] SESSION_SECRET must be set in production. Refusing to start.");
    process.exit(1);
  }
  console.warn("[config] SESSION_SECRET is not set; using an insecure development-only secret.");
}

const app = express();
app.locals.pool = pool;
app.disable("x-powered-by");
app.use(express.json({ limit: "1mb" }));
app.use(session({
  store: new pgSession({ pool, tableName: "user_sessions", createTableIfMissing: true }),
  secret: sessionSecret || "dev-only-insecure-secret",
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: "lax", secure: isProduction, maxAge: 1000 * 60 * 60 * 8 },
}));
app.use(express.static(path.join(__dirname, "public")));
app.use("/api/auth", authRoutes);
app.use("/api", resources);
app.use("/api/reports", reportsRoutes);
app.use("/api/products", productRoutes);
app.get("/api/health", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ success: true, message: "Retail Business OS is running" });
  } catch (err) {
    console.error("Health check failed:", err.message);
    res.status(503).json({ success: false, message: "Database unavailable" });
  }
});
app.get("/api/health/database", async (_req, res) => {
  try {
    const result = await pool.query("SELECT current_database() AS db, current_user AS usr");
    res.json({ success: true, message: "Database connection is working", database: result.rows[0].db, user: result.rows[0].usr });
  } catch (err) {
    console.error("Database error:", err.message);
    res.status(500).json({ success: false, message: "Database connection failed" });
  }
});
app.get("/api/protected-test", requireAuth, (req, res) => {
  res.json({ success: true, message: "You are authenticated", user: { id: req.user.id, username: req.user.username, name: req.user.name, role: req.user.role } });
});
app.get("/api/permission-test", requireAuth, requirePermission("MANAGE_PRODUCTS"), (req, res) => {
  res.json({ success: true, message: "You have MANAGE_PRODUCTS permission", role: req.user.role });
});
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ success: false, message: "An unexpected error occurred" });
});

const port = Number(process.env.PORT || 3000);

// Single source of truth for the role permission matrix (Phase 2). It is
// applied idempotently on every boot so existing installations converge with
// fresh schema.sql installs:
//   Admin          -> full access
//   Accountant     -> financials + inventory view + audit/analysis
//   Store/Godown   -> location-scoped operations and attendance
//   Manager        -> (their own location only, enforced in routes)
//   HR             -> people (users + attendance)
//   Delivery       -> drivers, vehicles and deliveries
// Legacy permission codes not listed here are left untouched.
const PERMISSION_MATRIX = [
  { role: "ADMIN", permissions: ["MANAGE_PRODUCTS", "MANAGE_STORES", "MANAGE_GODOWNS", "MANAGE_USERS", "VIEW_INVENTORY", "MANAGE_TRANSFERS", "MANAGE_DELIVERIES", "MANAGE_SALES", "MANAGE_FINANCIALS", "VIEW_ATTENDANCE", "MANAGE_ATTENDANCE", "VIEW_AUDIT"] },
  { role: "STORE_MANAGER", permissions: ["VIEW_INVENTORY", "MANAGE_TRANSFERS", "MANAGE_DELIVERIES", "MANAGE_SALES", "VIEW_ATTENDANCE", "MANAGE_ATTENDANCE"] },
  { role: "GODOWN_MANAGER", permissions: ["VIEW_INVENTORY", "MANAGE_TRANSFERS", "MANAGE_DELIVERIES", "VIEW_ATTENDANCE", "MANAGE_ATTENDANCE"] },
  { role: "DELIVERY_MANAGER", permissions: ["MANAGE_DELIVERIES"] },
  { role: "ACCOUNTANT", permissions: ["VIEW_INVENTORY", "MANAGE_FINANCIALS", "VIEW_AUDIT"] },
  { role: "HR", permissions: ["MANAGE_USERS", "VIEW_ATTENDANCE", "MANAGE_ATTENDANCE"] },
  { role: "STAFF", permissions: [] },
];

async function syncPermissionMatrix() {
  const managedCodes = [...new Set(PERMISSION_MATRIX.flatMap((m) => m.permissions))];
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    // Reset the canonical permissions only; legacy/extra grants stay intact.
    await client.query(
      `DELETE FROM role_permissions WHERE permission_id IN
        (SELECT id FROM permissions WHERE permission_code = ANY($1::text[]))`,
      [managedCodes]
    );
    // One round trip for the whole matrix instead of one INSERT per grant.
    const pairs = PERMISSION_MATRIX.flatMap(({ role, permissions }) => permissions.map((code) => [role, code]));
    await client.query(
      `INSERT INTO role_permissions(role, permission_id)
       SELECT m.role, p.id
       FROM unnest($1::text[], $2::text[]) AS m(role, code)
       JOIN permissions p ON p.permission_code = m.code
       ON CONFLICT DO NOTHING`,
      [pairs.map(([role]) => role), pairs.map(([, code]) => code)]
    );
    await client.query("COMMIT");
    console.log(`[db] Role permission matrix synced for ${PERMISSION_MATRIX.length} roles`);
  } catch (err) {
    await client.query("ROLLBACK");
    // Starting with a half-synced matrix could grant or deny the wrong access.
    throw new Error(`Permission matrix sync failed: ${err.message}`);
  } finally {
    client.release();
  }
}

// Idempotent schema updates applied on boot. They only relax/add columns
// that the feature set requires; they never drop or recreate tables.
// - Employees may exist without an account (username/password/role optional).
// - Sales carry client name and phone for customer/delivery information.
// - Smart-engine features rely on salesperson tracking (sales.created_by),
//   stock ageing (inventory.received_date), and delivery links for invoices
//   and stock transfers (deliveries.*). Legacy databases get the same shape.
const schemaUpdates = [
  "ALTER TABLE users ALTER COLUMN username DROP NOT NULL",
  "ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL",
  "ALTER TABLE users ALTER COLUMN role DROP NOT NULL",
  "ALTER TABLE sales ADD COLUMN IF NOT EXISTS client_name VARCHAR(200)",
  "ALTER TABLE sales ADD COLUMN IF NOT EXISTS client_phone VARCHAR(30)",
  "ALTER TABLE sales ADD COLUMN IF NOT EXISTS created_by INTEGER REFERENCES users(id)",
  "ALTER TABLE sales ADD COLUMN IF NOT EXISTS delivery_requested BOOLEAN NOT NULL DEFAULT FALSE",
  "ALTER TABLE sales ADD COLUMN IF NOT EXISTS delivery_address TEXT",
  "ALTER TABLE sales ADD COLUMN IF NOT EXISTS preferred_delivery_date DATE",
  "ALTER TABLE inventory ADD COLUMN IF NOT EXISTS received_date DATE DEFAULT CURRENT_DATE",
  "ALTER TABLE users ADD COLUMN IF NOT EXISTS job_title VARCHAR(120)",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS sale_id INTEGER REFERENCES sales(id)",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS stock_transfer_id INTEGER REFERENCES stock_transfers(id)",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS source_store_id INTEGER REFERENCES stores(id)",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS source_godown_id INTEGER REFERENCES godowns(id)",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS destination_store_id INTEGER REFERENCES stores(id)",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS destination_godown_id INTEGER REFERENCES godowns(id)",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS delivery_address TEXT",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS requested_date DATE",
  "ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS created_by INTEGER REFERENCES users(id)",
  // Indexes for the columns that dashboards, reports and scoped lists filter on.
  "CREATE INDEX IF NOT EXISTS sales_store_date_idx ON sales(store_id, sale_date)",
  "CREATE INDEX IF NOT EXISTS sales_sale_date_idx ON sales(sale_date)",
  "CREATE INDEX IF NOT EXISTS sales_created_by_idx ON sales(created_by)",
  "CREATE INDEX IF NOT EXISTS sale_items_sale_idx ON sale_items(sale_id)",
  "CREATE INDEX IF NOT EXISTS sale_items_product_idx ON sale_items(product_id)",
  "CREATE INDEX IF NOT EXISTS inventory_store_idx ON inventory(store_id)",
  "CREATE INDEX IF NOT EXISTS inventory_godown_idx ON inventory(godown_id)",
  "CREATE INDEX IF NOT EXISTS expenses_date_idx ON expenses(expense_date)",
  "CREATE INDEX IF NOT EXISTS attendance_date_idx ON attendance_records(date)",
  "CREATE INDEX IF NOT EXISTS deliveries_status_idx ON deliveries(status)",
  "CREATE INDEX IF NOT EXISTS stock_transfers_status_idx ON stock_transfers(status)",
  "CREATE INDEX IF NOT EXISTS audit_logs_created_at_idx ON audit_logs(created_at DESC)",
];

// Verify database connectivity before accepting traffic so that
// misconfiguration is caught immediately with a meaningful message.
pool.query("SELECT current_database() AS db, current_user AS usr")
  .then(async ({ rows }) => {
    console.log(`[db] Connected to "${rows[0].db}" as "${rows[0].usr}"`);
    for (const sql of schemaUpdates) {
      try {
        await pool.query(sql);
      } catch (err) {
        console.error("[db] Schema update failed:", err.message);
      }
    }
    await syncPermissionMatrix();
    console.log("[db] Schema updates applied");
    app.listen(port, () =>
      console.log(`Business OS running at http://localhost:${port}`)
    );
  })
  .catch((err) => {
    console.error("[db] Startup failed:", err.message);
    console.error("     Check DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD in your .env");
    process.exit(1);
  });
