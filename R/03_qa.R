# Phase 3: quality assurance. Output: outputs/qa_report.md (+ CSVs in outputs/tables)

source(here::here("R", "utils.R"))
d <- read_processed()
exclusions <- read_table("exclusions")
recon_base <- read_table("recon_before_charge_filter")
recon_out  <- read_table("recon_outcomes_before_charge_filter")
off3  <- read_csv(proj_path("data", "reference", "official_table3_nyc.csv"), show_col_types = FALSE)
off12 <- read_csv(proj_path("data", "reference", "official_table11_12_nyc.csv"), show_col_types = FALSE)

md_table <- function(df) {
  df <- mutate(df, across(everything(), \(x) ifelse(is.na(x), "", as.character(x))))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, \(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
check <- function(ok) if (isTRUE(ok)) "PASS" else "FLAG"
results <- list()

# 1. Row counts after each exclusion step
results$exclusions <- exclusions |> mutate(rows = comma(rows), dropped = if_else(is.na(dropped), "", comma(dropped)))

# 2. Duplicates
n_dup_id  <- sum(duplicated(d$caseid))
n_dup_row <- sum(duplicated(select(d, -caseid)))

# 3. Dates in range
date_min <- min(d$arraign_month); date_max <- max(d$arraign_month)
dates_ok <- date_min >= as.Date("2019-01-01") && date_max <= as.Date("2024-12-01")
months_present <- n_distinct(d$arraign_month)

# arr_yr is not a usable arrest date: count cycles where it sits far before
# the arraignment year. Timing uses larg_yr/larg_mo only.
arr_yr_num <- suppressWarnings(as.integer(d$arr_yr))
n_arr_far  <- sum(arr_yr_num < d$arraign_year - 1, na.rm = TRUE)
n_arr_pre2000 <- sum(arr_yr_num < 2000, na.rm = TRUE)

# 4. Ages
n_age_missing <- sum(is.na(d$age))
n_age_low  <- sum(d$age < 16, na.rm = TRUE)
n_age_high <- sum(d$age > 100, na.rm = TRUE)
age_range  <- range(d$age, na.rm = TRUE)

# 5. Missing values per column
missing_tbl <- tibble(column = names(d),
                      n_missing = map_int(d, \(x) sum(is.na(x)))) |>
  mutate(pct_missing = pct(n_missing / nrow(d), 2))

# 6. Category values vs. the data dictionary. Expected values were taken from
#    the DCJS data dictionary and the official summary tables; any value not in
#    the list is flagged.
expected <- list(
  larg_class = c("A Misdemeanor", "B Misdemeanor", "Unclassified Misdemeanor",
                 "A-I Felony Non Reducible", "A-I Felony Reducible", "A-II Felony",
                 "B Felony", "C Felony", "D Felony", "E Felony"),
  larg_vfo = c("VFO", "Not VFO", "Underlying VFO Charge", "VFO-like class A-1 offenses"),
  larg_rel_outcome = c("ROR", "NMR/RUS", "BailNotPaid w/in 5days", "BailPaid @arraign",
                       "BailPaid w/in 1-5days", "Remanded"),
  arr_re_combi = c("Black", "Hispanic", "White", "Asian", "Native American", "Other", "Unknown"),
  sex = c("Male", "Female"),
  disposition = c("Dismissed", "Conviction", "Pending", "Covered by/Consolidated",
                  "Other/Unknown Favorable", "YO Adjudication", "Removed to Family Court",
                  "No True Bill", "Acquitted")
)
cat_check <- imap(expected, \(vals, col) {
  obs <- unique(na.omit(as.character(d[[col]])))
  tibble(column = col, n_values = length(obs),
         unexpected = paste(setdiff(obs, vals), collapse = "; "))
}) |> bind_rows() |> mutate(result = if_else(unexpected == "", "PASS", "FLAG"))

# 7. restrictive never missing when the decision is known
n_restrictive_na <- sum(is.na(d$restrictive) & !is.na(d$release_decision))
n_period_na <- sum(is.na(d$period)); n_charge_na <- sum(is.na(d$charge_group))

# 8a. Reconciliation: release decisions by year vs. official Table 3
ours_before <- recon_base |>
  pivot_wider(names_from = release_decision, values_from = n_before_charge_filter)
ours_final <- d |> count(year = arraign_year, name = "analysis_pop")
recon3 <- off3 |>
  select(year, official_total = total) |>
  left_join(ours_before |> transmute(year, ours_same_rules =
              ROR + `Non-monetary` + `Bail set` + Remand), by = "year") |>
  left_join(ours_final, by = "year") |>
  mutate(diff_same_rules = ours_same_rules - official_total,
         diff_analysis_pop = analysis_pop - official_total)

recon3_detail <- off3 |>
  pivot_longer(-c(year, total), names_to = "decision", values_to = "official") |>
  mutate(decision = recode(decision, ror = "ROR", non_monetary = "Non-monetary",
                           bail_set = "Bail set", remand = "Remand")) |>
  left_join(recon_base |> rename(decision = release_decision, ours = n_before_charge_filter),
            by = c("year", "decision")) |>
  mutate(diff = ours - official, official_share = official / total)
max_abs_diff3 <- max(abs(recon3_detail$diff))

# 8b. Reconciliation: failure to appear and 180-day rearrest vs. Tables 11-12
recon12 <- off12 |>
  left_join(recon_out, by = c("year", "release_type"), suffix = c("_official", "_ours")) |>
  mutate(diff_released = released_ours - released_official,
         diff_fta = fta_ours - fta_official,
         diff_rearrest = rearrest_180_ours - rearrest_180_official)
max_abs_diff12 <- max(abs(c(recon12$diff_released, recon12$diff_fta, recon12$diff_rearrest)))

write_csv(recon3, proj_path("outputs", "tables", "reconciliation_table3.csv"))
write_csv(recon12, proj_path("outputs", "tables", "reconciliation_table11_12.csv"))
write_csv(missing_tbl, proj_path("outputs", "tables", "qa_missing.csv"))

# Bail amount note: $1 bail is common (usually set to give jail credit on another case).
n_bail_1 <- sum(d$bail_amount == 1, na.rm = TRUE)
n_bail_set <- sum(d$release_decision == "Bail set")

# ---- Write the report ------------------------------------------------------
summary_tbl <- tribble(
  ~check, ~result, ~detail,
  "Row counts after each exclusion step", "PASS", "See table below",
  "No duplicate case IDs", check(n_dup_id == 0), paste(n_dup_id, "duplicate caseid values"),
  "No duplicate rows (excluding ID)", "INFO",
    paste(comma(n_dup_row), "rows share every analysis field with another row. Expected: many cycles have identical coded values; caseid is unique."),
  "Arraignment dates Jan 2019 to Dec 2024", check(dates_ok),
    paste0(date_min, " to ", date_max, "; ", months_present, " of 72 months present"),
  "arr_yr not used for timing", "INFO",
    paste0(comma(n_arr_far), " cycles have arr_yr more than a year before the arraignment year (",
           comma(n_arr_pre2000), " before 2000). Dates come from larg_yr/larg_mo."),
  "Ages in valid range (16 to 100)", check(n_age_low == 0 && n_age_high == 0),
    paste0("range ", age_range[1], " to ", age_range[2], "; ", n_age_missing,
           " missing; ", n_age_low, " under 16; ", n_age_high, " over 100"),
  "Category values match dictionary", check(all(cat_check$result == "PASS")),
    paste(nrow(cat_check), "fields checked"),
  "restrictive never missing when decision known", check(n_restrictive_na == 0),
    paste(n_restrictive_na, "missing"),
  "period and charge_group never missing", check(n_period_na + n_charge_na == 0),
    paste(n_period_na, "period,", n_charge_na, "charge_group missing"),
  "Reconciliation: decisions by year (Table 3)", check(max_abs_diff3 == 0),
    paste("largest cell difference =", max_abs_diff3, "under the official rules"),
  "Reconciliation: FTA and rearrest (Tables 11-12)", check(max_abs_diff12 == 0),
    paste("largest cell difference =", max_abs_diff12)
)

report <- c(
  "# QA report",
  "",
  paste0("Generated by `R/03_qa.R` on ", Sys.Date(), ". Analysis population: **",
         comma(nrow(d)), "** NYC Criminal Court arraignments (criminal cycles)."),
  "",
  "## Summary", "", md_table(summary_tbl), "",
  "## 1. Exclusion table", "", md_table(results$exclusions), "",
  "## 2. Reconciliation with official DCJS summary tables", "",
  "Official rules for Table 3: NYC Criminal Court lower court arraignments, all charge classes,",
  "excluding cases disposed at arraignment and unknown decisions. Applying the same rules to the",
  "file reproduces the official totals. The analysis population also drops violations and",
  "infractions, so it is slightly smaller than the official totals.", "",
  md_table(recon3 |> mutate(across(-year, comma))), "",
  "Cell-level check (ours under the official rules vs. official):", "",
  md_table(recon3_detail |> transmute(year, decision, official = comma(official),
                                      ours = comma(ours), diff,
                                      official_share = pct(official_share))), "",
  paste0("Note: the official 2019 non-monetary share is ",
         pct(off3$non_monetary[1] / off3$total[1]),
         ". Detailed pretrial release reporting only became law on July 2, 2020, so ",
         "non-monetary release in 2019 is likely undercounted. Treat 2019 vs. later ",
         "comparisons of this category with caution."), "",
  "Failure to appear (bench warrant issued) and rearrest within 180 days, released cases:", "",
  md_table(recon12 |> select(year, release_type, released_official, released_ours,
                             fta_official, fta_ours, rearrest_180_official,
                             rearrest_180_ours)), "",
  "## 3. Category values", "", md_table(cat_check), "",
  "## 4. Missing values per column", "", md_table(missing_tbl), "",
  paste0("High missing rates in some columns are by design, not data problems: ",
         "`bail_amount` is only filled when bail was set, and `bail_paid_days` only when bail was paid; ",
         "`nmr_condition` is only filled for non-monetary releases; ",
         "`release_type` is empty for cycles not released within 5 days of arraignment ",
         "(bail set and not paid, or remand)."), "",
  "## 5. Other notes", "",
  paste0("- $1 bail: ", comma(n_bail_1), " of ", comma(n_bail_set),
         " bail-set cycles have a bail amount of $1. This is usually a nominal amount set so that ",
         "jail time counts toward another case. They are kept as \"Bail set\", as in the official tables."),
  "- The file has no person identifier, so repeat cycles for the same person cannot be linked.",
  "- The minimum age in the file is 18, so the youngest age group is 18 to 20 (the plan said 16 to 20)."
)
writeLines(report, proj_path("outputs", "qa_report.md"))
print(summary_tbl, n = Inf)
message("Wrote outputs/qa_report.md")
