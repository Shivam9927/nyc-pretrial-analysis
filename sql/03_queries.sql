-- 03_queries.sql
-- One query per output. Each block starts with "-- name: <output name>".
-- R/04_sql.R runs each block and saves it to outputs/tables/<name>.csv.

-- name: fig1_monthly_shares
SELECT arraign_month, period, release_decision, n, share
FROM decision_by_month
ORDER BY arraign_month, release_decision;

-- name: decision_shares_by_period
SELECT period, release_decision, n, share
FROM decision_by_period
ORDER BY period, release_decision;

-- name: decision_shares_by_year
SELECT arraign_year, release_decision, n, share, share_change_pts
FROM decision_by_year
ORDER BY arraign_year, release_decision;

-- name: fig2_restrictive_by_charge
SELECT charge_group, period, n, n_restrictive, restrictive_rate
FROM restrictive_by_charge_period
ORDER BY charge_group, period;

-- name: fig3_restrictive_by_borough
SELECT borough, period, n, restrictive_rate, rank_in_period
FROM restrictive_by_borough_period
ORDER BY period, rank_in_period;

-- name: fig4_outcomes_by_release
SELECT release_type, period, outcome, n, rate, ci_low, ci_high
FROM outcomes_by_release_period
ORDER BY outcome, release_type, period;

-- name: restrictive_by_year_charge
-- Year-level restrictive rate by charge group, with change from the prior year.
WITH yearly AS (
  SELECT arraign_year, charge_group,
         COUNT(*) AS n,
         AVG(restrictive) AS restrictive_rate
  FROM pretrial
  GROUP BY arraign_year, charge_group
)
SELECT *,
       restrictive_rate - LAG(restrictive_rate)
         OVER (PARTITION BY charge_group ORDER BY arraign_year) AS change_pts
FROM yearly
ORDER BY charge_group, arraign_year;

-- name: bail_paid_by_period
-- Among cycles where bail was set: share paid within 5 days, median bail amount.
SELECT period,
       COUNT(*) AS n_bail_set,
       AVG(bail_paid_5d) AS share_paid_5d,
       MEDIAN(bail_amount) FILTER (WHERE bail_amount > 1) AS median_bail_amount_over_1
FROM pretrial
WHERE release_decision = 'Bail set'
GROUP BY period
ORDER BY CASE period WHEN 'Pre-reform' THEN 1 WHEN 'Reform' THEN 2
                     WHEN 'First amendments' THEN 3 ELSE 4 END;

-- name: its_monthly_by_charge
-- Monthly restrictive rate by charge group, for the interrupted time series.
SELECT arraign_month, charge_group,
       COUNT(*) AS n,
       AVG(restrictive) AS restrictive_rate
FROM pretrial
GROUP BY arraign_month, charge_group
ORDER BY arraign_month, charge_group;

-- name: outcomes_by_nmr_condition
-- Non-monetary releases from 2020 on, by condition type and year.
SELECT arraign_year, nmr_condition,
       COUNT(*) AS n,
       AVG(bench_warrant) AS fta_rate,
       AVG(rearrest_180) AS rearrest_180_rate,
       COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY arraign_year) AS share_of_nmr
FROM pretrial
WHERE release_decision = 'Non-monetary'
GROUP BY arraign_year, nmr_condition
ORDER BY arraign_year, nmr_condition;
