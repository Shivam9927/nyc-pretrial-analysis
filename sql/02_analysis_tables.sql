-- 02_analysis_tables.sql
-- Summary tables used by the figures and the brief.
-- Shares use window functions over the counts in each group.

-- Release decision shares by month (Figure 1)
CREATE OR REPLACE TABLE decision_by_month AS
WITH counts AS (
  SELECT arraign_month, period, release_decision, COUNT(*) AS n
  FROM pretrial
  GROUP BY arraign_month, period, release_decision
)
SELECT arraign_month, period, release_decision, n,
       n * 1.0 / SUM(n) OVER (PARTITION BY arraign_month) AS share
FROM counts;

-- Release decision shares by period
CREATE OR REPLACE TABLE decision_by_period AS
WITH counts AS (
  SELECT period, release_decision, COUNT(*) AS n
  FROM pretrial
  GROUP BY period, release_decision
)
SELECT period, release_decision, n,
       n * 1.0 / SUM(n) OVER (PARTITION BY period) AS share
FROM counts;

-- Release decision shares by year, with year-over-year change in share
CREATE OR REPLACE TABLE decision_by_year AS
WITH counts AS (
  SELECT arraign_year, release_decision, COUNT(*) AS n
  FROM pretrial
  GROUP BY arraign_year, release_decision
),
shares AS (
  SELECT arraign_year, release_decision, n,
         n * 1.0 / SUM(n) OVER (PARTITION BY arraign_year) AS share
  FROM counts
)
SELECT *,
       share - LAG(share) OVER (PARTITION BY release_decision ORDER BY arraign_year)
         AS share_change_pts
FROM shares;

-- Restrictive rate (bail set or remand) by charge group and period (Figure 2)
CREATE OR REPLACE TABLE restrictive_by_charge_period AS
SELECT charge_group, period,
       COUNT(*) AS n,
       SUM(restrictive) AS n_restrictive,
       AVG(restrictive) AS restrictive_rate
FROM pretrial
GROUP BY charge_group, period;

-- Restrictive rate by borough and period (Figure 3)
CREATE OR REPLACE TABLE restrictive_by_borough_period AS
SELECT borough, period,
       COUNT(*) AS n,
       AVG(restrictive) AS restrictive_rate,
       RANK() OVER (PARTITION BY period ORDER BY AVG(restrictive) DESC) AS rank_in_period
FROM pretrial
GROUP BY borough, period;

-- Outcomes after release, by release type and period (Figure 4).
-- Released = ROR, non-monetary, or bail paid within 5 days (DCJS definition).
-- Bench warrant and rearrest are measured between arraignment and disposition,
-- rearrest_180 is within 180 days of arraignment.
CREATE OR REPLACE TABLE outcomes_by_release_period AS
WITH released AS (
  SELECT * FROM pretrial WHERE release_type IS NOT NULL
),
long AS (
  SELECT release_type, period, 'Bench warrant (FTA)' AS outcome, bench_warrant AS y FROM released
  UNION ALL
  SELECT release_type, period, 'Rearrest within 180 days', rearrest_180 FROM released
  UNION ALL
  SELECT release_type, period, 'Rearrest while pending', rearrest_pending FROM released
  UNION ALL
  SELECT release_type, period, 'Violent felony rearrest while pending', rearrest_vfo_pending FROM released
)
SELECT release_type, period, outcome,
       COUNT(*) AS n,
       AVG(y) AS rate,
       AVG(y) - 1.96 * SQRT(AVG(y) * (1 - AVG(y)) / COUNT(*)) AS ci_low,
       AVG(y) + 1.96 * SQRT(AVG(y) * (1 - AVG(y)) / COUNT(*)) AS ci_high
FROM long
GROUP BY release_type, period, outcome;
