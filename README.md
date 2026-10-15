# Business OS

Business OS is a role-based business management system. It contains no passwords or credentials.

## Setup

1. Configure a PostgreSQL database through `.env` using the variable names in `.env.example`.
2. Copy `.env.example` to `.env` and enter your own database values and a long session secret. Never commit `.env`.
3. Run `npm install` then `npm run create-admin -- "Your Name" admin`; it securely prompts for the password.
4. Start with `npm start`, then open `http://localhost:3000`.

On every boot the app re-applies a small set of idempotent schema updates and
re-syncs the role permission matrix, so a fresh install and an upgraded legacy
database always converge on the same capabilities.

## Permission matrix

- **Admin** — full access to every module, user, audit record, and delete action.
- **Accountant** — financials (expenses, salaries, bulk pay, linked payroll),
  inventory view, and analysis/audit.
- **Store Manager** — sales, inventory, transfers, deliveries, and attendance,
  restricted to their assigned store.
- **Godown Manager** — inventory, transfers, deliveries, and attendance,
  restricted to their assigned godown.
- **Delivery Manager** — drivers, vehicles, and deliveries.
- **HR** — employee accounts and attendance.
- **Staff** — dashboard only; managers record their operational activity.

Managers can mark and correct attendance for their own employees (and HR for
anyone). Location-scoped queries are enforced on every list and record the
manager touches, so no manager ever sees another location's numbers.

## Included workflows

- Add, edit, activate, and list products, stores, godowns, drivers, vehicles, deliveries, expenses, and salary records.
- Create users and assign their role and working location.
- Set inventory at a store or godown, with reorder levels.
- Create stock transfers and receive them. Stock only leaves the source location when a transfer is received, and insufficient stock is rejected.
- Record sales with one or more line items. The sale transaction deducts store inventory and is rejected when stock is insufficient.
- Mark attendance (individually or "Mark all present"); Store/Godown managers and HR can correct records, and daily history stays duplicate-free.
- Bulk-mark salaries as Paid and auto-calculate monthly pay from attendance.
- Filter inventory and sales by store and product from the toolbar dropdowns.
- View audit records and the summary dashboard.

## Smart engine

- **Analysis** — business totals, store performance, expense breakdown,
  attendance coverage, delivery status, salesperson ranking by revenue and
  average order value, and inventory ageing (30/60/90+ day "dead stock").
- **Predictive stock** — reorder insight from 30-day sales velocity and days of
  stock remaining.
- **Executive pulse** — a single daily summary (today's revenue, top
  salesperson, low stock, dead stock, absent staff) shown on the dashboard.
- **Omni-search** — one search box across products, customers, stores, godowns,
  drivers, vehicles, and sales (⌘ K).
- **Digital billing** — generate a PDF invoice per sale and trigger WhatsApp
  delivery via `WHATSAPP_WEBHOOK_URL` (mock mode without it).
- Global navigation is filtered by the permission matrix, so every user only
  sees the stores, products, and employees they are allowed to operate on.

## Database unification

Before consolidation, dump backups of both databases must exist. The one-time `npm run unify-database` script preserves legacy products, users (including password hashes only), and role capabilities in the configured target database. It adds the legacy stock-movement and multi-location-access structures without dropping or overwriting data. It intentionally does not migrate active sessions, so users sign in again after the move.
