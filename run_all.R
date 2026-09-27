# Runs the full pipeline in order: source("run_all.R") from the project root.
#
# Needs: tidyverse, arrow, duckdb, DBI, janitor, broom, scales, here, knitr,
#        rmarkdown, kableExtra, sandwich, lmtest. Rendering uses Quarto if it is installed,
#        otherwise rmarkdown (the .qmd files work with both).

required <- c("tidyverse", "arrow", "duckdb", "DBI", "janitor", "broom", "scales",
              "here", "knitr", "rmarkdown", "sandwich", "lmtest", "kableExtra")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  message("Installing missing packages: ", paste(missing, collapse = ", "))
  install.packages(missing)
}

t0 <- Sys.time()
step <- function(label, expr) {
  message("\n== ", label, " ==")
  force(expr)
  message("   done (", round(difftime(Sys.time(), t0, units = "mins"), 1), " min elapsed)")
}

step("1. Ingest and profile", source(here::here("R", "01_ingest.R")))
step("2. Clean and apply population rules", source(here::here("R", "02_clean.R")))
rm(raw_data); invisible(gc())
step("3. QA and reconciliation", source(here::here("R", "03_qa.R")))
step("4. SQL layer (DuckDB)", source(here::here("R", "04_sql.R")))

render_qmd <- function(file, pdf = FALSE) {
  path <- here::here("analysis", file)
  if (nzchar(Sys.which("quarto"))) {
    system2("quarto", c("render", shQuote(path)))
    out <- sub("\\.qmd$", if (pdf) ".pdf" else ".html", path)
    file.copy(out, here::here("outputs", basename(out)), overwrite = TRUE)
  } else {
    fmt <- if (pdf) rmarkdown::pdf_document(latex_engine = "xelatex", fig_caption = TRUE)
           else rmarkdown::html_document(toc = TRUE, self_contained = TRUE)
    rmarkdown::render(path, output_format = fmt, output_dir = here::here("outputs"),
                      quiet = TRUE, envir = new.env())
  }
}

step("5. Descriptives and Figures 1-4", render_qmd("01_descriptives.qmd"))
step("6. Regression and Figure 5", render_qmd("02_regression.qmd"))
step("7. Extensions: time series and condition types (Figures 6-7)",
     render_qmd("03_extensions.qmd"))
step("8. Research brief (PDF)", render_qmd("brief.qmd", pdf = TRUE))

message("\nAll done. See outputs/ (figures, tables, qa_report.md, brief.pdf).")
