-- 01_staging.sql
-- A view over the processed Parquet file. Paths are relative to the project root.
CREATE OR REPLACE VIEW pretrial AS
SELECT *
FROM read_parquet('data/processed/nyc_pretrial.parquet');
