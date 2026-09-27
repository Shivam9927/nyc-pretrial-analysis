# Data

## Source

NYS Division of Criminal Justice Services (DCJS), **Supplemental Pretrial Release Data File**, cases arraigned 2019 to 2024.
Landing page: https://criminaljustice.ny.gov/pretrial-release

| File | Link | Used for |
|---|---|---|
| Data file (zip of 2 CSVs) | https://itswebny.widen.net/s/jxjkjtfsd5/supplemental_pretrial_release_data_file | The data |
| Data dictionary | https://criminaljustice.ny.gov/supplemental-pretrial-release-data-dictionary | Column names and codes |
| Source notes | https://criminaljustice.ny.gov/supplemental-pretrial-release-data-source-notes | Definitions and caveats |
| Summary tables 2019 to 2024 | https://criminaljustice.ny.gov/supplemental-pretrial-release-summary-tables-2019-2024 | Reconciliation (see `reference/`) |

Unzip the two CSVs (`PretrialRelease_2019_2024_Part_1.csv`, `PretrialRelease_2019_2024_Part_2.csv`, about 800 MB together) into `data/raw/`. They are not committed (see `.gitignore`).

The raw file has 1,379,219 rows and 114 columns.

## Unit of analysis

One row is one **criminal cycle**: an arrest through its final disposition, which can cover several offenses and dockets. One person can appear more than once and there is no person ID. Results are counts of cycles, never counts of people. Counts will not match the main UCS docket-level file, and that is expected.

## Population rules

The analysis population is NYC Criminal Court arraignments from January 2019 to December 2024 with a felony or misdemeanor top charge and a known release decision. Rules are applied in this order in `R/02_clean.R`, and the row count after each is saved to `outputs/tables/exclusions.csv`.

| Step | Rule | Rows | Dropped |
|---|---|---:|---:|
| Raw file | All rows in both CSV parts | 1,379,219 | |
| NYC only | County of first arraignment is Bronx, Kings, New York, Queens or Richmond | 773,952 | 605,267 |
| NYC Criminal Court arraignments | `larg_court_type == "NYC Criminal Court"` (drops superior court originations, whose 2020 and 2021 data is incomplete) | 766,638 | 7,314 |
| Arraigned Jan 2019 to Dec 2024 | `larg_yr` 2019 to 2024 | 766,638 | 0 |
| Felony or misdemeanor | Drops violations, infractions, unspecified | 766,536 | 102 |
| Known release decision | Drops "Disposed at arraign" and "Unknown" (same rule as the official tables) | 628,938 | 137,598 |
| **Analysis population** | | **628,938** | |

"NYC" is defined by where the case was first arraigned, not by the arrest region (`arr_region`). This is what the official tables do: using the arraignment court reproduces the official NYC counts exactly, while using `arr_region` would drop about 600 NYC Criminal Court arraignments with a non-NYC or missing arrest region.

## Field choices

- **Dates.** All timing uses the lower court arraignment, `larg_yr` and `larg_mo`. Only month and year exist, so `arraign_month` is set to the 1st of the month. `arr_yr` is **not** used: it is not a reliable arrest date in this file (for example, the first row has `arr_yr` = 1981 for a 2019 arraignment, and 1,938 analysis cycles have `arr_yr` more than a year before arraignment).
- **Lower vs. superior court.** `larg_*` fields describe the lower court arraignment (NYC Criminal Court here); `uarg_*` fields describe a superior court arraignment. This project uses `larg_*` throughout.
- **Release decision** (`larg_rel_decision`): ROR; NMR/RUS (non-monetary release or release under supervision, labelled "Non-monetary"); Bail Set; Remanded. "Disposed at arraign" and "Unknown" are excluded.
- **restrictive** = 1 for bail set or remand, 0 for ROR or non-monetary.
- **charge_group** from `larg_class` and `larg_vfo`: violent felony (felony with `larg_vfo` of VFO, Underlying VFO Charge, or VFO-like class A-1), other felony, misdemeanor (A, B, unclassified).
- **Prior history:** `prior_felony_conv` (`pvfo_cnt` or `pnonvfo_cnt` above 0), `pending_case` (any `pend_*` = Yes), `prior_bw_2yrs` (`prearraign_bw_2yrs` = Yes).
- **age_group** from `arr_age`: 18 to 20, 21 to 24, 25 to 34, 35 to 49, 50+. The youngest age in the file is 18, so the plan's 16 to 20 group starts at 18.
- **race_eth** from `arr_re_combi` (combined race and ethnicity). Native American and Other are combined into "Other" because they are small. "Unknown" is set to missing.
- **borough** from `larg_county_name` (Kings = Brooklyn, New York = Manhattan, Richmond = Staten Island).
- **Released** (for outcomes) = ROR, non-monetary, or bail paid within 5 days (`larg_rel_outcome` = BailPaid @arraign or BailPaid w/in 1-5days). This is the DCJS definition.
- **bench_warrant** = `bw_issued` (a bench warrant issued between arraignment and disposition, used by DCJS as failure to appear).
- **rearrest_180** = any of `rearr_vfo_180`, `rearr_nonvfo_180`, `rearr_misd_180`. **rearrest_pending** = any of `rearr_vfo`, `rearr_nonvfo`, `rearr_misd`.

These definitions reproduce official DCJS Tables 3, 11 and 12 for NYC exactly (see `outputs/qa_report.md`). Confirm any field you add against the data dictionary.

## Periods

| Period | Months | What changed |
|---|---|---|
| Pre-reform | Jan to Dec 2019 | Old bail law |
| Reform | Jan to Jun 2020 | Bail eliminated for most misdemeanors and nonviolent felonies (effective Jan 1, 2020) |
| First amendments | Jul 2020 to May 2022 | More charges made bail eligible (effective Jul 2, 2020) |
| Later amendments | Jun 2022 to Dec 2024 | 2022 amendments (effective May 9, 2022) and 2023 amendments (effective June 2023) on judicial discretion |

Dates checked against the NYS Defenders Association bail reform page and legal summaries of the 2022 budget. May 2022 is a transition month (the 2022 amendments took effect May 9) and stays in "First amendments" as in the plan.

## Caveats

1. The unit is a criminal cycle, not a person or a docket.
2. **Pre-2020 release data is limited.** The law requiring detailed pretrial release reporting took effect July 2, 2020. Non-monetary release is 4.5% of 2019 NYC arraignments in both this file and the official tables, and it drops to almost zero from April to June 2020 before jumping in July 2020. Non-monetary release before July 2020 is likely undercounted, so 2019 comparisons need care.
3. Superior court data for 2020 and 2021 is incomplete. Keeping to NYC Criminal Court arraignments avoids this.
4. 2020 overlaps with COVID court closures and virtual arraignments.
5. Cases disposed at arraignment and unknown decisions are excluded, as in the official tables.
6. Dates are month-level only.
7. 22,972 of the 102,015 bail-set cycles in the analysis population have a bail amount of $1, usually a nominal amount so that jail time is credited to another case. They stay coded as bail set.
