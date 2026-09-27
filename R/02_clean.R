# Phase 2: recode, derive variables, apply population rules one at a time.
# Output: data/processed/nyc_pretrial.parquet (+ .rds), outputs/tables/exclusions.csv

source(here::here("R", "utils.R"))
if (!exists("raw_data", inherits = FALSE)) raw_data <- read_raw()

yes <- function(x) as.integer(!is.na(x) & x == "Yes")

# ---- 1. Derive variables on the full file --------------------------------
# Dates: use the LOWER COURT arraignment (larg_yr / larg_mo). arr_yr is not a
# reliable arrest date in this file (e.g. arr_yr = 1981 on a 2019 arraignment),
# so it is never used for timing. Only month and year are real; day is set to 1.
cases <- raw_data |>
  mutate(
    larg_yr_num = suppressWarnings(as.integer(larg_yr)),
    larg_mo_num = suppressWarnings(as.integer(larg_mo)),
    arraign_month = as.Date(sprintf("%04d-%02d-01", larg_yr_num, larg_mo_num)),

    # Where the case was first arraigned (lower court, else superior court).
    first_arraign_county = coalesce(larg_county_name, uarg_county_name),
    region = if_else(first_arraign_county %in% names(nyc_counties), "NYC", "Non-NYC",
                     missing = "Non-NYC"),

    # Release decision at the lower court arraignment.
    release_decision = case_match(larg_rel_decision,
      "ROR"       ~ "ROR",
      "NMR/RUS"   ~ "Non-monetary",
      "Bail Set"  ~ "Bail set",
      "Remanded"  ~ "Remand",
      .default = NA_character_),
    release_decision = factor(release_decision, levels = decision_levels),
    restrictive = case_when(
      release_decision %in% c("Bail set", "Remand")   ~ 1L,
      release_decision %in% c("ROR", "Non-monetary")  ~ 0L,
      TRUE ~ NA_integer_),

    # Period, by arraignment month. Law dates: reform 2020-01-01; first
    # amendments effective 2020-07-02; second amendments 2022-05-09; third
    # amendments 2023-06. With month-level dates, May 2022 is a transition
    # month and stays in "First amendments" as set in the project plan.
    period = case_when(
      arraign_month <  as.Date("2020-01-01") ~ "Pre-reform",
      arraign_month <  as.Date("2020-07-01") ~ "Reform",
      arraign_month <  as.Date("2022-06-01") ~ "First amendments",
      arraign_month <= as.Date("2024-12-01") ~ "Later amendments"),
    period = factor(period, levels = period_levels),

    # Charge at arraignment.
    is_felony = str_detect(coalesce(larg_class, ""), "Felony"),
    is_misd   = str_detect(coalesce(larg_class, ""), "Misdemeanor"),
    charge_group = case_when(
      is_felony & larg_vfo %in% c("VFO", "Underlying VFO Charge",
                                  "VFO-like class A-1 offenses") ~ "Violent felony",
      is_felony ~ "Other felony",
      is_misd   ~ "Misdemeanor"),
    charge_group = factor(charge_group, levels = charge_levels),
    firearm_charge = as.integer(larg_firearm %in% c("Top Charge is Firearm",
                                                    "Underlying Charge is Firearm")),

    # Prior history and status at arrest.
    prior_felony_conv = as.integer(pvfo_cnt != "0" | pnonvfo_cnt != "0"),
    prior_vfo_conv    = as.integer(pvfo_cnt != "0"),
    prior_misd_conv   = as.integer(pmisd_cnt != "0"),
    pending_case      = as.integer(yes(pend_vfo) | yes(pend_nonvfo) | yes(pend_misd)),
    prior_bw_2yrs     = yes(prearraign_bw_2yrs),

    # Demographics.
    age = suppressWarnings(as.integer(arr_age)),
    age_group = cut(age, breaks = c(-Inf, 20, 24, 34, 49, Inf), labels = age_levels),
    sex = na_if(arr_sex, "Unknown"),
    race_eth = case_match(arr_re_combi,
      c("Native American", "Other") ~ "Other",
      "Unknown" ~ NA_character_,
      .default = arr_re_combi),
    race_eth = factor(race_eth, levels = c("White", "Black", "Hispanic", "Asian", "Other")),
    borough = factor(unname(nyc_counties[larg_county_name]),
                     levels = c("Manhattan", "Bronx", "Brooklyn", "Queens", "Staten Island")),

    # Bail detail.
    bail_amount    = suppressWarnings(as.numeric(larg_bail_amount)),
    bail_paid_days = suppressWarnings(as.integer(larg_bail_paid_days)),
    bail_paid_5d   = as.integer(larg_rel_outcome %in% c("BailPaid @arraign",
                                                        "BailPaid w/in 1-5days")),

    # Released pretrial (DCJS definition: ROR, non-monetary, or bail paid
    # within 5 days of arraignment).
    release_type = case_when(
      release_decision == "ROR"          ~ "ROR",
      release_decision == "Non-monetary" ~ "Non-monetary",
      bail_paid_5d == 1                  ~ "Bail paid"),
    release_type = factor(release_type, levels = release_levels),

    # Outcomes between arraignment and disposition. bw_issued is "Not
    # Available" for Town and Village courts only (none in NYC).
    bench_warrant    = case_match(bw_issued, "Yes" ~ 1L, "No" ~ 0L, .default = NA_integer_),
    rearrest_180     = as.integer(yes(rearr_vfo_180) | yes(rearr_nonvfo_180) | yes(rearr_misd_180)),
    rearrest_pending = as.integer(yes(rearr_vfo) | yes(rearr_nonvfo) | yes(rearr_misd)),
    rearrest_vfo_pending = yes(rearr_vfo),
    days_arraign_to_disp = suppressWarnings(as.integer(days_btw_arg_disp)),

    # Non-monetary conditions (recorded from 2020 onward; all missing in 2019).
    cond_supervision = as.integer(larg_pretrial_supervision %in% "Y"),
    cond_contact     = as.integer(larg_contact_pretrial_service %in% "Y"),
    cond_electronic  = as.integer(larg_electronic_monitoring %in% "Y"),
    cond_no_weapons  = as.integer(larg_no_firearms_or_weapons %in% "Y"),
    cond_recorded    = !is.na(larg_pretrial_supervision),
    # One mutually exclusive group per non-monetary release, most intensive first.
    # Electronic monitoring is too rare to stand alone (under 200 NYC cases).
    nmr_condition = case_when(
      release_decision != "Non-monetary" ~ NA_character_,
      !cond_recorded                     ~ "Not recorded",
      cond_supervision == 1 | cond_electronic == 1 ~ "Pretrial supervision",
      cond_contact == 1                  ~ "Contact with pretrial services only",
      TRUE                               ~ "Other conditions only"),
    nmr_condition = factor(nmr_condition, levels = c(
      "Pretrial supervision", "Contact with pretrial services only",
      "Other conditions only", "Not recorded"))
  )

# ---- 2. Population rules, one at a time, with row counts ----------------
steps <- list(
  list("Raw file", "All rows in both CSV parts", \(d) d),
  list("NYC only", "First arraignment county is Bronx, Kings, New York, Queens or Richmond",
       \(d) filter(d, region == "NYC")),
  list("NYC Criminal Court arraignments",
       "Lower court arraignment in NYC Criminal Court (drops superior court originations)",
       \(d) filter(d, larg_court_type == "NYC Criminal Court")),
  list("Arraigned Jan 2019 to Dec 2024", "larg_yr between 2019 and 2024",
       \(d) filter(d, between(larg_yr_num, 2019, 2024), !is.na(larg_mo_num))),
  list("Felony or misdemeanor", "Drops violations, infractions, unspecified or missing class",
       \(d) filter(d, is_felony | is_misd)),
  list("Known release decision", "Drops disposed at arraignment and unknown decisions",
       \(d) filter(d, !is.na(release_decision)))
)

exclusions <- tibble(step = character(), rule = character(), rows = integer())
pop <- cases
for (s in steps) {
  pop <- s[[3]](pop)
  exclusions <- add_row(exclusions, step = s[[1]], rule = s[[2]], rows = nrow(pop))
}
exclusions <- exclusions |>
  mutate(dropped = lag(rows) - rows) |>
  add_row(step = "Analysis population", rule = "", rows = nrow(pop), dropped = NA)
print(exclusions)

# Keep the counts needed for QA reconciliation (before the charge filter).
recon_frame <- cases |>
  filter(region == "NYC", larg_court_type == "NYC Criminal Court",
         between(larg_yr_num, 2019, 2024), !is.na(release_decision))
recon_base <- recon_frame |>
  count(year = larg_yr_num, release_decision, name = "n_before_charge_filter")
recon_outcomes <- recon_frame |>
  filter(!is.na(release_type)) |>
  group_by(year = larg_yr_num, release_type) |>
  summarise(released = n(), fta = sum(bench_warrant, na.rm = TRUE),
            rearrest_180 = sum(rearrest_180), .groups = "drop")

# ---- 3. Save -------------------------------------------------------------
keep <- c("caseid", "arraign_month", "larg_yr_num", "larg_mo_num", "period",
          "borough", "larg_class", "larg_vfo", "charge_group", "firearm_charge",
          "release_decision", "restrictive", "larg_rel_outcome", "release_type",
          "bail_amount", "bail_paid_days", "bail_paid_5d",
          "prior_felony_conv", "prior_vfo_conv", "prior_misd_conv", "pending_case",
          "prior_bw_2yrs", "age", "age_group", "sex", "race_eth", "arr_re_combi",
          "arr_yr", "bench_warrant", "rearrest_180", "rearrest_pending",
          "rearrest_vfo_pending", "disposition", "days_arraign_to_disp",
          "nmr_condition", "cond_supervision", "cond_contact", "cond_electronic",
          "cond_no_weapons")

nyc_pretrial <- pop |>
  select(all_of(keep)) |>
  rename(arraign_year = larg_yr_num, arraign_mo = larg_mo_num)

dir.create(proj_path("outputs", "tables"), showWarnings = FALSE, recursive = TRUE)
write_csv(exclusions, proj_path("outputs", "tables", "exclusions.csv"))
write_csv(recon_base, proj_path("outputs", "tables", "recon_before_charge_filter.csv"))
write_csv(recon_outcomes, proj_path("outputs", "tables", "recon_outcomes_before_charge_filter.csv"))
write_processed(nyc_pretrial)
message("Analysis population: ", comma(nrow(nyc_pretrial)), " criminal cycles")
