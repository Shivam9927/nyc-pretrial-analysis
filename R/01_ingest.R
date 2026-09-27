# Phase 1-2: read the raw files and profile every column.
# Output: outputs/profile/column_profile.csv, outputs/profile/categorical_counts.csv

source(here::here("R", "utils.R"))

raw_data <- read_raw()
message("Raw rows: ", comma(nrow(raw_data)), "  columns: ", ncol(raw_data))

# Column profile: missingness, distinct values, and an example value.
# Every column is character at this stage by design.
column_profile <- tibble(
  column     = names(raw_data),
  type_read  = map_chr(raw_data, \(x) class(x)[1]),
  n_missing  = map_int(raw_data, \(x) sum(is.na(x))),
  pct_missing = round(100 * n_missing / nrow(raw_data), 2),
  n_distinct = map_int(raw_data, n_distinct),
  example    = map_chr(raw_data, \(x) { v <- x[!is.na(x)]; if (length(v)) v[1] else NA_character_ })
)

# count() of every categorical field (any column with 60 or fewer distinct values).
cat_cols <- column_profile$column[column_profile$n_distinct <= 60]
categorical_counts <- map(cat_cols, \(col) {
  raw_data |> count(value = .data[[col]], sort = TRUE) |> mutate(column = col, .before = 1)
}) |> bind_rows()

dir.create(proj_path("outputs", "profile"), showWarnings = FALSE, recursive = TRUE)
write_csv(column_profile, proj_path("outputs", "profile", "column_profile.csv"))
write_csv(categorical_counts, proj_path("outputs", "profile", "categorical_counts.csv"))
message("Profile written for ", ncol(raw_data), " columns (", length(cat_cols), " categorical).")
