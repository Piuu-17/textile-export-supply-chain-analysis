-- =====================================================================
-- Textile Export Supply Chain Analysis | 03_analysis_queries.sql   (PostgreSQL)
-- Each query answers one business question; the notebook reproduces the same numbers.
-- =====================================================================


-- Q1. Monthly revenue with year-over-year growth -------------------------------------------
WITH monthly AS (
    SELECT to_char(order_date, 'YYYY-MM') AS month,
           SUM(quantity * unit_price_usd) AS revenue_usd
    FROM sales_orders
    GROUP BY 1
)
SELECT month,
       ROUND(revenue_usd / 1000000, 2) AS revenue_musd,
       ROUND(100.0 * (revenue_usd - LAG(revenue_usd, 12) OVER (ORDER BY month))
             / LAG(revenue_usd, 12) OVER (ORDER BY month), 1) AS yoy_growth_pct
FROM monthly
ORDER BY month;


-- Q2. Revenue by product category and year -------------------------------------------------
SELECT k.category,
       EXTRACT(YEAR FROM o.order_date)::int AS year,
       ROUND(SUM(o.quantity * o.unit_price_usd) / 1000000, 2) AS revenue_musd
FROM sales_orders o
JOIN sku_master k ON k.sku = o.sku
GROUP BY k.category, EXTRACT(YEAR FROM o.order_date)
ORDER BY year, revenue_musd DESC;


-- Q3. Top 10 customers and their cumulative share of revenue -------------------------------
WITH cust AS (
    SELECT customer_id, SUM(quantity * unit_price_usd) AS revenue
    FROM sales_orders
    GROUP BY customer_id
)
SELECT customer_id,
       ROUND(revenue / 1000000, 2) AS revenue_musd,
       ROUND(100 * revenue / SUM(revenue) OVER (), 1) AS share_pct,
       ROUND(100 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 1) AS cumulative_share_pct
FROM cust
ORDER BY revenue DESC
LIMIT 10;


-- Q4. OTIF (On-Time-In-Full) by region -----------------------------------------------------
-- on-time: delivered on/before promised date | in-full: delivered quantity >= ordered quantity
SELECT region,
       COUNT(*) AS orders,
       ROUND(100.0 * AVG((delivery_date <= promised_date)::int), 1) AS on_time_pct,
       ROUND(100.0 * AVG((delivered_qty >= quantity)::int), 1)      AS in_full_pct,
       ROUND(100.0 * AVG((delivery_date <= promised_date AND delivered_qty >= quantity)::int), 1) AS otif_pct
FROM sales_orders
WHERE order_status = 'Delivered'
GROUP BY region
ORDER BY otif_pct;


-- Q5. Sea freight: peak season (Aug-Oct) vs rest of the year -------------------------------
SELECT CASE WHEN EXTRACT(MONTH FROM order_date) IN (8, 9, 10)
            THEN 'Peak (Aug-Oct)' ELSE 'Off-peak' END AS season,
       COUNT(*) AS sea_orders,
       ROUND(100.0 * AVG((delivery_date <= promised_date)::int), 1) AS on_time_pct,
       ROUND(100.0 * AVG((delivered_qty >= quantity)::int), 1)      AS in_full_pct,
       ROUND(100.0 * AVG((delivery_date <= promised_date AND delivered_qty >= quantity)::int), 1) AS otif_pct
FROM sales_orders
WHERE order_status = 'Delivered' AND shipping_mode = 'Sea'
GROUP BY 1;


-- Q6. Supplier scorecard (score = 50% on-time + 30% quality + 20% price, out of 100) -------
WITH market AS (        -- average price paid per material per month, across all suppliers
    SELECT material, to_char(po_date, 'YYYY-MM') AS month, AVG(price_per_kg_inr) AS mkt_price
    FROM purchase_orders
    GROUP BY 1, 2
),
metrics AS (
    SELECT s.supplier_name, s.material,
           COUNT(*)                                                       AS pos,
           SUM(p.quantity_kg * p.price_per_kg_inr) / 1000000              AS spend_inr_m,
           AVG((p.actual_lead_days <= p.promised_lead_days)::int)         AS on_time,
           AVG(p.actual_lead_days - p.promised_lead_days)                 AS avg_delay_days,
           AVG(p.defect_rate_pct)                                         AS defect_pct,
           100 * AVG(p.price_per_kg_inr / m.mkt_price)                    AS price_index
    FROM purchase_orders p
    JOIN suppliers s ON s.supplier_id = p.supplier_id
    JOIN market m    ON m.material = p.material AND m.month = to_char(p.po_date, 'YYYY-MM')
    GROUP BY s.supplier_name, s.material
)
SELECT supplier_name, material, pos,
       ROUND(spend_inr_m, 1)       AS spend_inr_m,
       ROUND(100 * on_time, 1)     AS on_time_pct,
       ROUND(avg_delay_days, 2)    AS avg_delay_days,
       ROUND(defect_pct, 2)        AS defect_pct,
       ROUND(price_index, 1)       AS price_index,
       ROUND(100 * (0.5 * on_time
                  + 0.3 * GREATEST(LEAST(1 - defect_pct / 3, 1), 0)
                  + 0.2 * GREATEST(LEAST(1 - (price_index - 95) / 30, 1), 0)), 1) AS score
FROM metrics
ORDER BY score DESC;


-- Q7. Raw cotton: domestic vs imported suppliers --------------------------------------------
SELECT CASE WHEN s.location LIKE '%Import%' THEN 'Imported' ELSE 'Domestic' END AS source,
       COUNT(*) AS pos,
       ROUND(SUM(p.quantity_kg * p.price_per_kg_inr) / SUM(p.quantity_kg), 1)       AS price_inr_per_kg,
       ROUND(AVG(p.actual_lead_days), 1)                                           AS avg_lead_days,
       ROUND(100.0 * AVG((p.actual_lead_days <= p.promised_lead_days)::int), 1)    AS on_time_pct
FROM purchase_orders p
JOIN suppliers s ON s.supplier_id = p.supplier_id
WHERE p.material = 'Raw Cotton'
GROUP BY 1;


-- Q8. Stock-outs and estimated lost revenue in 2024, by product -----------------------------
SELECT i.sku, k.product_name,
       COUNT(*) FILTER (WHERE i.stockout_units > 0)              AS stockout_months,
       SUM(i.stockout_units)                                      AS stockout_units,
       ROUND(SUM(i.stockout_units * k.base_price_usd) / 1000000, 2) AS est_lost_revenue_musd,
       ROUND(AVG(i.closing_stock), 0)                             AS avg_stock
FROM inventory_monthly i
JOIN sku_master k ON k.sku = i.sku
WHERE i.month LIKE '2024-%'
GROUP BY i.sku, k.product_name
ORDER BY est_lost_revenue_musd DESC;


-- Q9. Economic order (batch) quantity per product, from 2024 demand -------------------------
-- EOQ = sqrt(2 * annual demand * set-up cost / yearly holding cost per unit)
WITH demand AS (
    SELECT sku, SUM(quantity) AS annual_demand
    FROM sales_orders
    WHERE order_date >= DATE '2024-01-01' AND order_date < DATE '2025-01-01'
    GROUP BY sku
)
SELECT k.sku, k.product_name, d.annual_demand,
       ROUND(SQRT(2.0 * d.annual_demand * k.ordering_cost_usd
                  / (k.unit_cost_usd * k.holding_cost_pct)))::int AS eoq
FROM demand d
JOIN sku_master k ON k.sku = d.sku
ORDER BY k.sku;
