const { Pool } = require("pg");
const os = require("os");

// Safe local fallbacks so the app always connects to the correct
// Retail Business OS database even when no .env file is present.
// DB_NAME always resolves to business_os_2; DB_USER falls back to the
// current OS user (which has peer-auth access on the local socket).
const pool = new Pool({
  // When DB_HOST is not set, pg uses the Unix socket at DB_SOCKET_PATH
  // (or /tmp on macOS Homebrew / Postgres.app). Passing undefined here
  // tells the pg driver to use the socket, matching pg_isready behaviour.
  host: process.env.DB_HOST || undefined,
  port: Number(process.env.DB_PORT || 5432),
  // Critical: never default to the OS username as the database name.
  database: process.env.DB_NAME || "business_os_2",
  // Fall back to the OS username only for the PG role (not the database).
  user: process.env.DB_USER || os.userInfo().username,
  password: process.env.DB_PASSWORD || undefined,
});

// Emit a clear startup diagnostic so misconfiguration is caught immediately.
pool.on("error", (err) => {
  console.error("[db] Unexpected pool error:", err.message);
});

module.exports = pool;
