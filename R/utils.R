# Shared helpers used by every script and notebook.
# All paths are built from the project root so scripts work from any folder.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(stringr)
  library(purrr)
})

proj_path <- function(...) {
  root <- if (requireNamespace("here", quietly = TRUE)) here::here() else getwd()
  file.path(root, ...)
}

# Official NYC borough names for the five counties.
nyc_counties <- c(
  "Bronx" = "Bronx", "Kings" = "Brooklyn", "New York" = "Manhattan",
  "Queens" = "Queens", "Richmond" = "Staten Island"
)

# janitor::clean_names() when installed; a base-R equivalent otherwise.
clean_names_safe <- function(df) {
  if (requireNamespace("janitor", quietly = TRUE)) return(janitor::clean_names(df))
  nm <- tolower(names(df))
  nm <- gsub("[^a-z0-9]+", "_", nm)
  nm <- gsub("^_|_$", "", nm)
  names(df) <- make.unique(nm, sep = "_")
  df
}

# Read every raw CSV part with all columns as character, so nothing is
# silently converted (Phase 2, step 1).
read_raw <- function(dir = proj_path("data", "raw")) {
  files <- list.files(dir, pattern = "^PretrialRelease_2019_2024_Part_\\d+\\.csv$",
                      full.names = TRUE)
  if (length(files) == 0) {
    stop("No raw CSVs found in data/raw/. See data/README.md for the download link.")
  }
  message("Reading ", length(files), " raw file(s)...")
  files |>
    map(\(f) read_csv(f, col_types = cols(.default = col_character()),
                      na = c(""), progress = FALSE)) |>
    bind_rows() |>
    clean_names_safe()
}

# Processed data: Parquet is the analysis file (arrow). An .rds copy is also
# written because it loads fastest inside R.
processed_parquet <- function() proj_path("data", "processed", "nyc_pretrial.parquet")
processed_rds     <- function() proj_path("data", "processed", "nyc_pretrial.rds")

write_processed <- function(df) {
  dir.create(dirname(processed_rds()), showWarnings = FALSE, recursive = TRUE)
  saveRDS(df, processed_rds())
  if (requireNamespace("arrow", quietly = TRUE)) {
    arrow::write_parquet(df, processed_parquet())
    message("Wrote ", processed_parquet())
  } else if (requireNamespace("duckdb", quietly = TRUE)) {
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
    duckdb::duckdb_register(con, "df", df)
    DBI::dbExecute(con, sprintf("COPY df TO '%s' (FORMAT PARQUET)", processed_parquet()))
    message("Wrote ", processed_parquet(), " (via duckdb)")
  } else {
    csv <- proj_path("data", "processed", "nyc_pretrial.csv")
    write_csv(df, csv)
    warning("Neither arrow nor duckdb is installed. Wrote ", csv,
            " instead of Parquet. Install arrow to follow the plan exactly.")
  }
}

read_processed <- function() {
  if (file.exists(processed_rds())) return(readRDS(processed_rds()))
  if (requireNamespace("arrow", quietly = TRUE) && file.exists(processed_parquet())) {
    return(arrow::read_parquet(processed_parquet()))
  }
  stop("Processed data not found. Run R/02_clean.R first.")
}

read_table <- function(name) {
  read_csv(proj_path("outputs", "tables", paste0(name, ".csv")),
           show_col_types = FALSE)
}

# Shared factor levels so every table and figure uses the same order.
decision_levels <- c("ROR", "Non-monetary", "Bail set", "Remand")
period_levels   <- c("Pre-reform", "Reform", "First amendments", "Later amendments")
charge_levels   <- c("Violent felony", "Other felony", "Misdemeanor")
age_levels      <- c("18-20", "21-24", "25-34", "35-49", "50+")
release_levels  <- c("ROR", "Non-monetary", "Bail paid")

pct <- function(x, digits = 1) paste0(formatC(100 * x, format = "f", digits = digits), "%")
comma <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
