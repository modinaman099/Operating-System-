-- Business OS. Use the database-unification script when consolidating an existing installation.
CREATE TABLE permissions (id SERIAL PRIMARY KEY, permission_code VARCHAR(80) UNIQUE NOT NULL, description TEXT);
CREATE TABLE users (
  id SERIAL PRIMARY KEY, full_name VARCHAR(200) NOT NULL, username VARCHAR(100) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL, role VARCHAR(30) NOT NULL CHECK (role IN ('ADMIN','STORE_MANAGER','GODOWN_MANAGER','DELIVERY_MANAGER','ACCOUNTANT','HR','STAFF')),
  store_id INTEGER, godown_id INTEGER, status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE role_permissions (role VARCHAR(30) NOT NULL, permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE, PRIMARY KEY(role, permission_id));
CREATE TABLE stores (id SERIAL PRIMARY KEY, store_name VARCHAR(200) NOT NULL, store_code VARCHAR(50) UNIQUE NOT NULL, address TEXT, phone VARCHAR(30), status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE godowns (id SERIAL PRIMARY KEY, godown_name VARCHAR(200) NOT NULL, godown_code VARCHAR(50) UNIQUE NOT NULL, address TEXT, phone VARCHAR(30), status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
ALTER TABLE users ADD CONSTRAINT users_store_fk FOREIGN KEY (store_id) REFERENCES stores(id), ADD CONSTRAINT users_godown_fk FOREIGN KEY (godown_id) REFERENCES godowns(id);
CREATE TABLE products (id SERIAL PRIMARY KEY, product_name VARCHAR(200) NOT NULL, product_code VARCHAR(100) UNIQUE NOT NULL, category VARCHAR(100), unit VARCHAR(50) NOT NULL, selling_price NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(selling_price >= 0), cost_price NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(cost_price >= 0), status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE inventory (id SERIAL PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES products(id), store_id INTEGER REFERENCES stores(id), godown_id INTEGER REFERENCES godowns(id), quantity NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(quantity >= 0), reorder_level NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(reorder_level >= 0), received_date DATE NOT NULL DEFAULT CURRENT_DATE, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CHECK ((store_id IS NULL) <> (godown_id IS NULL)));
CREATE UNIQUE INDEX inventory_store_product_unique ON inventory(product_id,store_id) WHERE store_id IS NOT NULL;
CREATE UNIQUE INDEX inventory_godown_product_unique ON inventory(product_id,godown_id) WHERE godown_id IS NOT NULL;
CREATE TABLE stock_transfers (id SERIAL PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES products(id), from_store_id INTEGER REFERENCES stores(id), from_godown_id INTEGER REFERENCES godowns(id), to_store_id INTEGER REFERENCES stores(id), to_godown_id INTEGER REFERENCES godowns(id), quantity NUMERIC(12,2) NOT NULL CHECK(quantity > 0), status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','IN_TRANSIT','RECEIVED','CANCELLED')), notes TEXT, created_by INTEGER REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE drivers (id SERIAL PRIMARY KEY, driver_name VARCHAR(200) NOT NULL, phone VARCHAR(30), license_number VARCHAR(100) UNIQUE, status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE vehicles (id SERIAL PRIMARY KEY, vehicle_number VARCHAR(50) UNIQUE NOT NULL, vehicle_type VARCHAR(80), capacity NUMERIC(12,2), status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE deliveries (id SERIAL PRIMARY KEY, delivery_number VARCHAR(60) UNIQUE NOT NULL, store_id INTEGER REFERENCES stores(id), driver_id INTEGER REFERENCES drivers(id), vehicle_id INTEGER REFERENCES vehicles(id), status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','ASSIGNED','OUT_FOR_DELIVERY','DELIVERED','CANCELLED')), delivery_date DATE, notes TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE sales (id SERIAL PRIMARY KEY, sale_number VARCHAR(60) UNIQUE NOT NULL, store_id INTEGER NOT NULL REFERENCES stores(id), sale_date DATE NOT NULL DEFAULT CURRENT_DATE, total_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(total_amount >= 0), payment_mode VARCHAR(30), created_by INTEGER REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE sale_items (id SERIAL PRIMARY KEY, sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE, product_id INTEGER NOT NULL REFERENCES products(id), quantity NUMERIC(12,2) NOT NULL CHECK(quantity > 0), unit_price NUMERIC(12,2) NOT NULL CHECK(unit_price >= 0));
CREATE TABLE expenses (id SERIAL PRIMARY KEY, expense_date DATE NOT NULL DEFAULT CURRENT_DATE, category VARCHAR(100) NOT NULL, amount NUMERIC(12,2) NOT NULL CHECK(amount >= 0), description TEXT, store_id INTEGER REFERENCES stores(id), godown_id INTEGER REFERENCES godowns(id), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE attendance_records (id SERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), date DATE NOT NULL, status VARCHAR(20) NOT NULL CHECK(status IN ('PRESENT','ABSENT','LEAVE','HALF_DAY')), time_status VARCHAR(20), marked_by INTEGER REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(user_id,date));
CREATE TABLE salaries (id SERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), month DATE NOT NULL, basic_amount NUMERIC(12,2) NOT NULL DEFAULT 0, bonus NUMERIC(12,2) NOT NULL DEFAULT 0, deductions NUMERIC(12,2) NOT NULL DEFAULT 0, payment_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK(payment_status IN ('PENDING','PAID')), paid_on DATE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(user_id,month));
CREATE TABLE audit_logs (id BIGSERIAL PRIMARY KEY, user_id INTEGER REFERENCES users(id), action VARCHAR(50) NOT NULL, entity_type VARCHAR(80) NOT NULL, entity_id INTEGER, details JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
INSERT INTO permissions (permission_code,description) VALUES
('MANAGE_PRODUCTS','Create, edit and deactivate products'),('MANAGE_STORES','Create and manage stores'),('MANAGE_GODOWNS','Create and manage godowns'),('MANAGE_USERS','Create and manage users'),('VIEW_INVENTORY','View inventory'),('MANAGE_TRANSFERS','Create and manage stock transfers'),('MANAGE_DELIVERIES','Manage drivers, vehicles and deliveries'),('MANAGE_SALES','Record and view sales'),('MANAGE_FINANCIALS','Manage expenses and salaries'),('VIEW_ATTENDANCE','View attendance'),('MANAGE_ATTENDANCE','Mark attendance'),('VIEW_AUDIT','View audit records');
-- Role permission matrix (Phase 2): Admin full access; Accountant financials;
-- Store/Godown managers location-scoped operations; HR people; Delivery manager logistics.
INSERT INTO role_permissions(role,permission_id) SELECT 'ADMIN',id FROM permissions;
INSERT INTO role_permissions(role,permission_id) SELECT 'STORE_MANAGER',id FROM permissions WHERE permission_code IN ('VIEW_INVENTORY','MANAGE_TRANSFERS','MANAGE_DELIVERIES','MANAGE_SALES','VIEW_ATTENDANCE','MANAGE_ATTENDANCE');
INSERT INTO role_permissions(role,permission_id) SELECT 'GODOWN_MANAGER',id FROM permissions WHERE permission_code IN ('VIEW_INVENTORY','MANAGE_TRANSFERS','MANAGE_DELIVERIES','VIEW_ATTENDANCE','MANAGE_ATTENDANCE');
INSERT INTO role_permissions(role,permission_id) SELECT 'ACCOUNTANT',id FROM permissions WHERE permission_code IN ('VIEW_INVENTORY','MANAGE_FINANCIALS','VIEW_AUDIT');
INSERT INTO role_permissions(role,permission_id) SELECT 'DELIVERY_MANAGER',id FROM permissions WHERE permission_code IN ('MANAGE_DELIVERIES');
INSERT INTO role_permissions(role,permission_id) SELECT 'HR',id FROM permissions WHERE permission_code IN ('MANAGE_USERS','VIEW_ATTENDANCE','MANAGE_ATTENDANCE');
-- Indexes for dashboard, report and location-scoped queries (also applied on boot by server.js).
CREATE INDEX sales_store_date_idx ON sales(store_id, sale_date);
CREATE INDEX sales_sale_date_idx ON sales(sale_date);
CREATE INDEX sales_created_by_idx ON sales(created_by);
CREATE INDEX sale_items_sale_idx ON sale_items(sale_id);
CREATE INDEX sale_items_product_idx ON sale_items(product_id);
CREATE INDEX inventory_store_idx ON inventory(store_id);
CREATE INDEX inventory_godown_idx ON inventory(godown_id);
CREATE INDEX expenses_date_idx ON expenses(expense_date);
CREATE INDEX attendance_date_idx ON attendance_records(date);
CREATE INDEX deliveries_status_idx ON deliveries(status);
CREATE INDEX stock_transfers_status_idx ON stock_transfers(status);
CREATE INDEX audit_logs_created_at_idx ON audit_logs(created_at DESC);
