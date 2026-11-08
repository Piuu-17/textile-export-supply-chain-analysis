# Textile Export Supply Chain Analysis

Supply chain analysis for a home-textile exporter (towels, bed linen, yarn) using **Python** and **PostgreSQL**. It looks at four questions: how reliably orders are delivered, which suppliers are best, whether stock levels are right, and how much customers will order next.

> **About the data:** the dataset is **synthetic**. Real company data is confidential, so `generate_data.py` creates five related tables (orders, purchases, suppliers, products, inventory) with realistic patterns such as a festive-season peak and late deliveries in busy months. The numbers are illustrative; the methods work the same on real data.

## What it covers

| Question | Method |
|---|---|
| Are orders delivered **on time and in full (OTIF)**? | OTIF by region, shipping mode and season |
| Which **suppliers** are reliable and good value? | Score out of 100: on-time 50%, quality 30%, price 20% |
| Is **inventory** at the right level? | EOQ, safety stock, actual vs target stock, stock-outs |
| How much will customers **order next quarter**? | Linear regression (trend + seasonality) vs seasonal naive baseline |

## Key results

- **OTIF is 69.3%**; in the Aug-Oct peak, sea-freight OTIF drops from **77.0% to 51.1%**.
- Four weak cotton suppliers hold **59.6% of cotton spend**; imported cotton costs **31% more** and takes **42 days vs 8**.
- Three products ran out of stock in 2024, about **US$4.35M** of revenue at list price.
- The forecast (regression averaged with seasonal naive) has **15.1% monthly error** vs 17.3% for the seasonal naive baseline.

![Sales](images/sales_overview.png)
![OTIF](images/otif_analysis.png)
![Suppliers](images/supplier_scorecard.png)
![Inventory](images/inventory_vs_target.png)
![Forecast](images/forecast_vs_actual.png)

## Project structure

```
textile-export-supply-chain-analysis/
├── data/
│   ├── sales_orders.csv        # 7,063 export orders (2023-2024)
│   ├── purchase_orders.csv     # 1,244 raw-material purchase orders
│   ├── inventory_monthly.csv   # month-end stock by product
│   ├── sku_master.csv          # price, cost, lead time per product
│   └── suppliers.csv
├── notebooks/
│   └── supply_chain_analysis.ipynb     # full analysis with outputs
├── sql/
│   ├── 01_schema.sql                   # PostgreSQL tables
│   ├── 02_load_data.sql                # loads the CSV files
│   └── 03_analysis_queries.sql         # 9 business queries
├── images/
├── generate_data.py                    # recreates the dataset (seed = 42)
└── requirements.txt
```

## How to run

**Notebook**
```bash
pip install -r requirements.txt
jupyter notebook notebooks/supply_chain_analysis.ipynb
```

**PostgreSQL** (run these from the repository root)
```bash
createdb textile_supply_chain
psql -d textile_supply_chain -f sql/01_schema.sql
psql -d textile_supply_chain -f sql/02_load_data.sql
psql -d textile_supply_chain -f sql/03_analysis_queries.sql
```

## Definitions

- **On-time:** delivered on or before the promised date
- **In-full:** delivered quantity is at least the ordered quantity
- **OTIF:** both together (orders still in transit are excluded)
- **EOQ:** sqrt(2 x annual demand x set-up cost / yearly holding cost per unit)
- **Safety stock:** 1.65 x std dev of daily demand x sqrt(lead time), for a 95% service level
- **WAPE:** sum of absolute forecast errors / sum of actual demand

## Limitations

- Synthetic data: re-run on real data before drawing business conclusions.
- No freight cost or currency effects (cotton prices are in INR, sales in USD).
- Stock-outs are treated as lost sales at list price.
- Safety stock ignores lead-time variability to keep the formula simple.

## Tech stack

Python (NumPy, pandas, scikit-learn, matplotlib) · PostgreSQL · Jupyter
