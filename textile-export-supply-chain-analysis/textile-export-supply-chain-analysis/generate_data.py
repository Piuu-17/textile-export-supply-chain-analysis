"""
generate_data.py
----------------
Creates the synthetic textile-exporter supply-chain dataset used in this project.

Why synthetic?  Real company data (orders, supplier performance, inventory) is confidential,
and no public dataset covers a textile exporter end-to-end
(orders -> raw cotton procurement -> inventory).  This script builds a realistic one,
with the patterns a real supply-chain analyst would look for (export seasonality, peak-season
freight delays, supplier reliability differences, cotton price cycles, customer concentration).

All company / supplier / customer names are FICTIONAL.
Run:  python generate_data.py     (fixed random seed -> identical CSVs every time)
"""
import numpy as np
import pandas as pd
from pathlib import Path

rng = np.random.default_rng(42)
OUT = Path(__file__).parent / "data"
OUT.mkdir(exist_ok=True)

START, END = pd.Timestamp("2023-01-01"), pd.Timestamp("2024-12-31")
DATA_CUTOFF = END  # orders delivered after this date are still 'In Transit'

# ------------------------------------------------------------------ 1. SKU master
skus = pd.DataFrame([
    # sku, name, category, uom, base price USD, unit cost USD, ordering cost USD, holding %/yr, production lead days
    ("TWL-01", "Bath Towel 600 GSM",       "Bath Linen", "pcs", 4.20, 2.90, 120, 0.22, 21),
    ("TWL-02", "Hand Towel 500 GSM",       "Bath Linen", "pcs", 1.60, 1.10, 100, 0.22, 18),
    ("BED-01", "Bed Sheet Set 300 TC",     "Bed Linen",  "set", 9.50, 6.60, 150, 0.20, 25),
    ("BED-02", "Duvet Cover 300 TC",       "Bed Linen",  "pcs", 11.80, 8.20, 150, 0.20, 28),
    ("YRN-01", "Combed Cotton Yarn 30s",   "Yarn",       "kg",  3.10, 2.55, 200, 0.18, 10),
], columns=["sku", "product_name", "category", "uom", "base_price_usd", "unit_cost_usd",
            "ordering_cost_usd", "holding_cost_pct", "production_lead_days"])
sku_w = {"TWL-01": .30, "TWL-02": .15, "BED-01": .25, "BED-02": .12, "YRN-01": .18}
qty_median = {"TWL-01": 9000, "TWL-02": 12000, "BED-01": 5000, "BED-02": 3500, "YRN-01": 7000}

# ------------------------------------------------------------------ 2. Customers
regions = ["USA", "Europe", "UK", "India", "Middle East", "Australia"]
region_w = np.array([.38, .25, .10, .12, .08, .07])
cust_region = rng.choice(regions, size=45, p=region_w)
cust_weight = rng.lognormal(0, 1.4, 45)          # heavy tail -> a few big retailers dominate
cust_weight /= cust_weight.sum()
customers = pd.DataFrame({"customer_id": [f"CUST-{i:03d}" for i in range(1, 46)],
                          "region": cust_region})

region_cfg = {   # sea/road lead days, mean delay, sd delay, price factor
    "USA": (38, -2.2, 3.5, 1.05), "Europe": (32, -2.8, 3.0, 1.08), "UK": (31, -2.8, 3.0, 1.06),
    "India": (6, -0.5, 1.5, 0.88), "Middle East": (20, -2.0, 3.0, 0.96), "Australia": (34, -1.8, 4.0, 1.02),
}
season = np.array([.85, .80, .85, .90, .90, .95, 1.05, 1.20, 1.30, 1.25, 1.10, .95])  # Jan..Dec (export peak Aug-Oct)

# ------------------------------------------------------------------ 3. Sales orders
rows = []
for d in pd.date_range(START, END):
    growth = 1 + 0.15 * (d - START).days / 365
    lam = 9.0 * season[d.month - 1] * growth * (0.55 if d.dayofweek == 6 else 1.0)
    for _ in range(rng.poisson(lam)):
        rows.append(d)
orders = pd.DataFrame({"order_date": rows})
n = len(orders)
cidx = rng.choice(len(customers), size=n, p=cust_weight)
orders["customer_id"] = customers.customer_id.values[cidx]
orders["region"] = customers.region.values[cidx]
orders["sku"] = rng.choice(list(sku_w), size=n, p=list(sku_w.values()))
orders["quantity"] = [int(round(rng.lognormal(np.log(qty_median[s]), 0.5), -2)) or 100 for s in orders.sku]
base = orders.sku.map(skus.set_index("sku").base_price_usd)
rf = orders.region.map({k: v[3] for k, v in region_cfg.items()})
orders["unit_price_usd"] = (base * rf * rng.lognormal(0, 0.04, n)).round(2)

mode, promised_days, actual_days = [], [], []
for r, m in zip(orders.region, orders.order_date.dt.month):
    lead, mu, sd, _ = region_cfg[r]
    if r == "India":
        md, pl, delay = "Road", lead, rng.normal(mu, sd)
    elif rng.random() < 0.10:
        md, pl, delay = "Air", 8, rng.normal(-1.0, 1.5)
    else:
        md, pl = "Sea", lead
        delay = rng.normal(mu, sd) + (2.2 if m in (8, 9, 10) else 0)   # peak-season port congestion
    mode.append(md); promised_days.append(pl); actual_days.append(max(pl + int(round(delay)), pl - 3))
orders["shipping_mode"] = mode
orders["promised_date"] = orders.order_date + pd.to_timedelta(promised_days, unit="D")
orders["delivery_date"] = orders.order_date + pd.to_timedelta(actual_days, unit="D")

peak = orders.order_date.dt.month.isin([8, 9, 10])
p_full = np.where(peak, 0.88, 0.93)
full = rng.random(n) < p_full
orders["delivered_qty"] = np.where(full, orders.quantity,
                                   (orders.quantity * rng.uniform(0.80, 0.99, n)).round().astype(int))
in_transit = orders.delivery_date > DATA_CUTOFF
orders["order_status"] = np.where(in_transit, "In Transit", "Delivered")
orders.loc[in_transit, ["delivery_date", "delivered_qty"]] = [pd.NaT, np.nan]
orders["delivered_qty"] = orders["delivered_qty"].astype("Int64")
orders = orders.sort_values("order_date").reset_index(drop=True)
orders.insert(0, "order_id", [f"SO-{i:06d}" for i in range(1, len(orders) + 1)])
orders = orders[["order_id", "order_date", "customer_id", "region", "sku", "quantity", "unit_price_usd",
                 "shipping_mode", "promised_date", "delivery_date", "delivered_qty", "order_status"]]

# ------------------------------------------------------------------ 4. Suppliers & purchase orders
sup = [  # id, name, state/country, material, promised lead, delay mean, delay sd, defect mean %, price factor
    ("SUP-01", "Malwa Cotton Traders",      "Punjab",         "Raw Cotton",     7, -0.5, 1.5, 1.2, 1.00),
    ("SUP-02", "Haryana Ginning Co",        "Haryana",        "Raw Cotton",     6,  1.0, 3.0, 1.8, 0.97),
    ("SUP-03", "Saurashtra Fibres",         "Gujarat",        "Raw Cotton",     8, -1.0, 1.0, 0.9, 1.03),
    ("SUP-04", "Vidarbha Agro Cotton",      "Maharashtra",    "Raw Cotton",     9,  2.0, 4.0, 2.4, 0.95),
    ("SUP-05", "Deccan Lint Suppliers",     "Telangana",      "Raw Cotton",     9,  0.0, 2.0, 1.4, 0.99),
    ("SUP-06", "Nile Delta Imports",        "Egypt (Import)", "Raw Cotton",    35,  4.0, 7.0, 0.8, 1.35),
    ("SUP-07", "Pacific Cotton Exports",    "Australia (Import)", "Raw Cotton", 40,  2.0, 5.0, 0.7, 1.25),
    ("SUP-08", "Vapi ColorChem",            "Gujarat",        "Dyes & Chemicals", 5, -0.5, 1.5, 1.0, 1.00),
    ("SUP-09", "Ankleshwar Dyestuffs",      "Gujarat",        "Dyes & Chemicals", 6,  0.5, 2.5, 1.5, 0.94),
    ("SUP-10", "Hyderabad Specialty Chem",  "Telangana",      "Dyes & Chemicals", 7,  0.0, 2.0, 1.1, 1.05),
    ("SUP-11", "Ludhiana Carton Works",     "Punjab",         "Packaging",      4, -1.0, 1.0, 0.6, 1.00),
    ("SUP-12", "Baddi Poly Pack",           "Himachal Pradesh", "Packaging",    4,  0.5, 2.0, 1.0, 0.96),
]
suppliers = pd.DataFrame(sup, columns=["supplier_id", "supplier_name", "location", "material",
                                       "promised_lead_days", "_dm", "_ds", "_def", "_pf"])
sup_public = suppliers[["supplier_id", "supplier_name", "location", "material"]]

# monthly raw-cotton price index (INR/kg): mean-reverting walk + harvest-season dip (Oct-Feb)
months = pd.period_range("2023-01", "2024-12", freq="M")
cot, p = [], 162.0
for m in months:
    harvest = -10 if m.month in (10, 11, 12, 1, 2) else (8 if m.month in (5, 6, 7, 8) else 0)
    p = p + 0.25 * (162 + harvest - p) + rng.normal(0, 2.2)
    cot.append(p)
mkt = {"Raw Cotton": dict(zip(months, cot)), "Dyes & Chemicals": 520.0, "Packaging": 95.0}
med_qty = {"Raw Cotton": 40000, "Dyes & Chemicals": 3000, "Packaging": 5000}

po_rows = []
for d in pd.date_range(START, END):
    for _ in range(rng.poisson(1.7)):
        mat = rng.choice(["Raw Cotton", "Dyes & Chemicals", "Packaging"], p=[.60, .25, .15])
        s = suppliers[suppliers.material == mat].sample(1, random_state=int(rng.integers(1e9))).iloc[0]
        base_p = mkt[mat][d.to_period("M")] if mat == "Raw Cotton" else mkt[mat] * (1 + rng.normal(0, 0.02))
        price = round(base_p * s._pf * rng.lognormal(0, 0.015), 2)
        qty = int(round(rng.lognormal(np.log(med_qty[mat]), 0.45), -2)) or 100
        actual = max(int(s.promised_lead_days + round(rng.normal(s._dm, s._ds))), int(s.promised_lead_days) - 2)
        defect = round(max(0.0, rng.normal(s._def, 0.6)), 2)
        if rng.random() < 0.01:
            defect = np.nan                                  # a few lots were never inspected
        po_rows.append((d, s.supplier_id, mat, qty, price, int(s.promised_lead_days), actual,
                        d + pd.Timedelta(days=actual), defect, int(rng.choice([30, 45, 60], p=[.5, .3, .2]))))
po = pd.DataFrame(po_rows, columns=["po_date", "supplier_id", "material", "quantity_kg", "price_per_kg_inr",
                                    "promised_lead_days", "actual_lead_days", "receipt_date",
                                    "defect_rate_pct", "payment_terms_days"])
po.insert(0, "po_id", [f"PO-{i:05d}" for i in range(1, len(po) + 1)])

# ------------------------------------------------------------------ 5. Monthly inventory
o = orders.copy()
o["month"] = o.order_date.dt.to_period("M")
dem = o.pivot_table(index="month", columns="sku", values="quantity", aggfunc="sum")
inv_rows = []
for s in skus.sku:
    d = dem[s].values
    opening = d[0] * 0.45
    prev = np.insert(d[:-1], 0, d[0])
    for i, m in enumerate(dem.index):
        produced = (0.75 * prev[i] + 0.25 * d[i]) * rng.uniform(0.88, 1.12)   # reactive planning: lags demand
        avail = opening + produced
        shipped = min(d[i], avail)
        stockout = d[i] - shipped
        closing = avail - shipped
        inv_rows.append((str(m), s, round(opening), round(produced), round(shipped), round(stockout), round(closing)))
        opening = closing
inventory = pd.DataFrame(inv_rows, columns=["month", "sku", "opening_stock", "units_produced",
                                            "units_shipped", "stockout_units", "closing_stock"])

# ------------------------------------------------------------------ 6. Save
skus.to_csv(OUT / "sku_master.csv", index=False)
sup_public.to_csv(OUT / "suppliers.csv", index=False)
orders.to_csv(OUT / "sales_orders.csv", index=False, date_format="%Y-%m-%d")
po.to_csv(OUT / "purchase_orders.csv", index=False, date_format="%Y-%m-%d")
inventory.to_csv(OUT / "inventory_monthly.csv", index=False)
for f in sorted(OUT.glob("*.csv")):
    print(f"{f.name:24s} {len(pd.read_csv(f)):>6,} rows")
