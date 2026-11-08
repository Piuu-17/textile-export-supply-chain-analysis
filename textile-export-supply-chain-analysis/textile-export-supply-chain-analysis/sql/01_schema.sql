-- =====================================================================
-- Textile Export Supply Chain Analysis | 01_schema.sql   (PostgreSQL)
-- Usage:  psql -d textile_supply_chain -f sql/01_schema.sql
-- =====================================================================

DROP TABLE IF EXISTS inventory_monthly CASCADE;
DROP TABLE IF EXISTS purchase_orders   CASCADE;
DROP TABLE IF EXISTS sales_orders      CASCADE;
DROP TABLE IF EXISTS suppliers         CASCADE;
DROP TABLE IF EXISTS sku_master        CASCADE;

CREATE TABLE sku_master (
    sku                   VARCHAR(10)  PRIMARY KEY,
    product_name          VARCHAR(60)  NOT NULL,
    category              VARCHAR(30)  NOT NULL,   -- Bath Linen / Bed Linen / Yarn
    uom                   VARCHAR(10)  NOT NULL,   -- pcs, set, kg
    base_price_usd        NUMERIC(8,2) NOT NULL,
    unit_cost_usd         NUMERIC(8,2) NOT NULL,
    ordering_cost_usd     NUMERIC(8,2) NOT NULL,   -- set-up cost per production batch
    holding_cost_pct      NUMERIC(4,2) NOT NULL,   -- yearly holding cost as a fraction of unit cost
    production_lead_days  INTEGER      NOT NULL
);

CREATE TABLE suppliers (
    supplier_id    VARCHAR(10) PRIMARY KEY,
    supplier_name  VARCHAR(60) NOT NULL,
    location       VARCHAR(40) NOT NULL,
    material       VARCHAR(30) NOT NULL            -- Raw Cotton / Dyes & Chemicals / Packaging
);

CREATE TABLE sales_orders (
    order_id        VARCHAR(12)  PRIMARY KEY,
    order_date      DATE         NOT NULL,
    customer_id     VARCHAR(10)  NOT NULL,
    region          VARCHAR(20)  NOT NULL,
    sku             VARCHAR(10)  NOT NULL REFERENCES sku_master (sku),
    quantity        INTEGER      NOT NULL CHECK (quantity > 0),
    unit_price_usd  NUMERIC(8,2) NOT NULL CHECK (unit_price_usd > 0),
    shipping_mode   VARCHAR(10)  NOT NULL,         -- Sea / Air / Road
    promised_date   DATE         NOT NULL,
    delivery_date   DATE,                          -- NULL while the order is still in transit
    delivered_qty   INTEGER,
    order_status    VARCHAR(15)  NOT NULL          -- Delivered / In Transit
);

CREATE TABLE purchase_orders (
    po_id               VARCHAR(12)   PRIMARY KEY,
    po_date             DATE          NOT NULL,
    supplier_id         VARCHAR(10)   NOT NULL REFERENCES suppliers (supplier_id),
    material            VARCHAR(30)   NOT NULL,
    quantity_kg         INTEGER       NOT NULL,
    price_per_kg_inr    NUMERIC(10,2) NOT NULL,
    promised_lead_days  INTEGER       NOT NULL,
    actual_lead_days    INTEGER       NOT NULL,
    receipt_date        DATE          NOT NULL,
    defect_rate_pct     NUMERIC(5,2),              -- NULL = lot not inspected
    payment_terms_days  INTEGER       NOT NULL
);

CREATE TABLE inventory_monthly (
    month           CHAR(7)    NOT NULL,           -- 'YYYY-MM'
    sku             VARCHAR(10) NOT NULL REFERENCES sku_master (sku),
    opening_stock   INTEGER    NOT NULL,
    units_produced  INTEGER    NOT NULL,
    units_shipped   INTEGER    NOT NULL,
    stockout_units  INTEGER    NOT NULL,           -- demand that could not be served from stock
    closing_stock   INTEGER    NOT NULL,
    PRIMARY KEY (month, sku)
);

CREATE INDEX idx_sales_order_date ON sales_orders (order_date);
CREATE INDEX idx_sales_region     ON sales_orders (region);
CREATE INDEX idx_po_supplier_date ON purchase_orders (supplier_id, po_date);
