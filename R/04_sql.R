# Phase 4: SQL layer in DuckDB.
# Runs sql/01_staging.sql and sql/02_analysis_tables.sql, then each named query
# in sql/03_queries.sql, saving results to outputs/tables/<name>.csv.

source(here::here("R", "utils.R"))
library(DBI)

# Split a SQL file into statements (comment lines removed first).
sql_statements <- function(path) {
  lines <- readLines(path)
  lines <- lines[!grepl("^\\s*--", lines)]
  stmts <- strsplit(paste(lines, collapse = "\n"), ";")[[1]]
  stmts[nzchar(trimws(stmts))]
}

# Named blocks from 03_queries.sql ("-- name: xxx").
sql_named_queries <- function(path) {
  txt <- paste(readLines(path), collapse = "\n")
  blocks <- strsplit(txt, "\n-- name: ")[[1]][-1]
  set_names(
    map_chr(blocks, \(b) sub("^[^\n]*\n", "", b)),
    map_chr(blocks, \(b) trimws(sub("\n.*$", "", b)))
  )
}

# Everything runs inside a function so the connection stays open until the
# end. (on.exit() at the top level of a sourced script fires straight away.)
run_sql_layer <- function() {
  old_wd <- setwd(proj_path())          # parquet path in the SQL is relative to the root
  on.exit(setwd(old_wd), add = TRUE)

  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  for (f in c("sql/01_staging.sql", "sql/02_analysis_tables.sql")) {
    for (s in sql_statements(f)) dbExecute(con, s)
    message("Ran ", f)
  }

  queries <- sql_named_queries("sql/03_queries.sql")
  for (name in names(queries)) {
    res <- dbGetQuery(con, queries[[name]])
    write_csv(res, file.path("outputs", "tables", paste0(name, ".csv")))
    message("  ", name, ": ", nrow(res), " rows")
  }
  invisible(names(queries))
}

run_sql_layer()
