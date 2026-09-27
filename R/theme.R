# One shared look for every figure (white background, light grid, 11 pt text).
suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
})

theme_pretrial <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background   = element_rect(fill = "white", colour = NA),
      panel.background  = element_rect(fill = "white", colour = NA),
      panel.grid.major  = element_line(colour = "grey90", linewidth = 0.3),
      panel.grid.minor  = element_blank(),
      axis.ticks        = element_blank(),
      axis.text         = element_text(colour = "grey30"),
      axis.title        = element_text(colour = "grey30", size = rel(0.9)),
      plot.title        = element_text(face = "bold", size = rel(1.1), colour = "grey10"),
      plot.subtitle     = element_text(colour = "grey35", size = rel(0.9),
                                       margin = margin(b = 8)),
      plot.caption      = element_text(colour = "grey45", size = rel(0.72), hjust = 0,
                                       margin = margin(t = 8)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      legend.position   = "top",
      legend.justification = "left",
      legend.title      = element_blank(),
      legend.text       = element_text(colour = "grey25"),
      strip.text        = element_text(face = "bold", colour = "grey20", hjust = 0),
      plot.margin       = margin(10, 14, 8, 10)
    )
}

# Okabe-Ito colours. The same release decision always gets the same colour.
decision_colors <- c(
  "ROR"          = "#009E73",
  "Non-monetary" = "#56B4E9",
  "Bail set"     = "#E69F00",
  "Remand"       = "#D55E00",
  "Bail paid"    = "#E69F00"   # released after bail: same family as bail set
)

# Periods are ordered in time, so they use one light-to-dark ramp.
period_colors <- c(
  "Pre-reform"       = "#BDBDBD",
  "Reform"           = "#9ECAE1",
  "First amendments" = "#4292C6",
  "Later amendments" = "#08519C"
)

source_caption <- function(n, extra = NULL, width = 120) {
  src <- paste0(
    "Source: NYS DCJS Supplemental Pretrial Release Data File. NYC Criminal Court ",
    "arraignments, Jan 2019 to Dec 2024, felony or misdemeanor top charge, known ",
    "release decision. n = ", format(n, big.mark = ","), " criminal cycles."
  )
  paste(strwrap(c(extra, src), width = width), collapse = "\n")
}

save_fig <- function(plot, name, width = 7, height = 4.5) {
  path <- file.path(proj_path("outputs", "figures"), paste0(name, ".png"))
  ggsave(path, plot, width = width, height = height, dpi = 300, bg = "white")
  invisible(path)
}
