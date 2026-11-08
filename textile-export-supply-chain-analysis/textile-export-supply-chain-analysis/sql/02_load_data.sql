-- =====================================================================
-- Textile Export Supply Chain Analysis | 02_load_data.sql   (PostgreSQL)
-- Run from the REPOSITORY ROOT so the relative paths below resolve:
--     psql -d textile_supply_chain -f sql/02_load_data.sql
-- (\copy is a psql command; in pgAdmin use right-click table > Import/Export Data instead)
-- =====================================================================

\copy sku_master        FROM 'data/sku_master.csv'        WITH (FORMAT csv, HEADER true)
\copy suppliers         FROM 'data/suppliers.csv'         WITH (FORMAT csv, HEADER true)
\copy sales_orders      FROM 'data/sales_orders.csv'      WITH (FORMAT csv, HEADER true)
\copy purchase_orders   FROM 'data/purchase_orders.csv'   WITH (FORMAT csv, HEADER true)
\copy inventory_monthly FROM 'data/inventory_monthly.csv' WITH (FORMAT csv, HEADER true)

-- quick check: expect 5, 12, 7063, 1244, 120
SELECT 'sku_master' AS table_name, COUNT(*) AS rows FROM sku_master
UNION ALL SELECT 'suppliers',         COUNT(*) FROM suppliers
UNION ALL SELECT 'sales_orders',      COUNT(*) FROM sales_orders
UNION ALL SELECT 'purchase_orders',   COUNT(*) FROM purchase_orders
UNION ALL SELECT 'inventory_monthly', COUNT(*) FROM inventory_monthly;
