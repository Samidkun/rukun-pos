-- +goose Up
CREATE TABLE IF NOT EXISTS events (
    server_seq BIGSERIAL PRIMARY KEY,
    event_id TEXT NOT NULL UNIQUE,
    terminal_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    op TEXT NOT NULL,
    payload JSONB NOT NULL,
    hlc TEXT,
    status TEXT NOT NULL DEFAULT 'applied',
    reject_reason TEXT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_events_server_seq ON events (server_seq);
CREATE INDEX IF NOT EXISTS idx_events_device_seq ON events (device_id, server_seq);
CREATE INDEX IF NOT EXISTS idx_events_entity ON events (entity_type, entity_id);

CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT,
    price_cents BIGINT NOT NULL,
    updated_hlc TEXT,
    deleted BOOLEAN NOT NULL DEFAULT false,
    catalog_version BIGINT NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_products_catalog_version ON products (catalog_version);

CREATE TABLE IF NOT EXISTS sales (
    id TEXT PRIMARY KEY,
    invoice_series TEXT NOT NULL,
    invoice_number BIGINT NOT NULL,
    terminal_id TEXT NOT NULL,
    total_cents BIGINT NOT NULL,
    payment_method TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_terminal_invoice UNIQUE (terminal_id, invoice_series, invoice_number)
);

CREATE INDEX IF NOT EXISTS idx_sales_occurred_at ON sales (occurred_at);

CREATE TABLE IF NOT EXISTS sale_items (
    id TEXT PRIMARY KEY,
    sale_id TEXT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL,
    name TEXT NOT NULL,
    price_cents BIGINT NOT NULL,
    qty INT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items (sale_id);

CREATE TABLE IF NOT EXISTS stock_movements (
    id TEXT PRIMARY KEY,
    product_id TEXT NOT NULL,
    delta INT NOT NULL,
    reason TEXT NOT NULL,
    sale_id TEXT,
    hlc TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id);

CREATE TABLE IF NOT EXISTS catalog_version (
    id INT PRIMARY KEY DEFAULT 1,
    version BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO catalog_version (id, version, updated_at)
VALUES (1, 1, now())
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS devices (
    device_id TEXT PRIMARY KEY,
    terminal_id TEXT NOT NULL,
    last_seen_seq BIGINT NOT NULL DEFAULT 0,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- +goose Down
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS catalog_version;
DROP TABLE IF EXISTS stock_movements;
DROP TABLE IF EXISTS sale_items;
DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS events;
