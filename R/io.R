# Output helpers: every table carries the decay-correction mode, every run writes a run_info file.

#' Write a CSV to output/ (or elsewhere) with the decay-correction mode as first column.
write_output <- function(df, path, cfg) {
  df <- cbind(DECAY_CORRECTION = decay_label(cfg$decay_correction$to_injection), df)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(df, path, row.names = FALSE, na = "")
  message("  wrote ", path, " (", nrow(df), " rows)")
  invisible(path)
}

git_commit <- function() {
  out <- tryCatch(
    suppressWarnings(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)),
    error = function(e) NA_character_
  )
  dirty <- tryCatch(
    length(suppressWarnings(system2("git", c("status", "--porcelain"), stdout = TRUE, stderr = FALSE))) > 0,
    error = function(e) NA
  )
  if (length(out) == 0 || is.na(out[1])) return("unknown")
  paste0(out[1], if (isTRUE(dirty)) " (uncommitted changes)" else "")
}

#' Traceability record: time, git commit, R/package versions, input checksums, full config.
write_run_info <- function(path, cfg, inputs, step) {
  pkgs <- c("PKNCA", "aNCA", "renv")
  versions <- vapply(pkgs, function(p) {
    if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else "not installed"
  }, character(1))
  md5 <- tools::md5sum(inputs)
  lines <- c(
    paste("Step:", step),
    paste("Run at (UTC):", format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")),
    paste("Git commit:", git_commit()),
    paste("R:", R.version.string),
    paste0("Package ", pkgs, ": ", versions),
    paste("Decay correction:", decay_label(cfg$decay_correction$to_injection)),
    paste0("Physical half-life used: ", cfg$nuclide$half_life, " ", cfg$nuclide$half_life_unit,
           " (", signif(cfg$nuclide$half_life_h, 6), " h), nuclide ", cfg$nuclide$name),
    "",
    "Input files (MD5):",
    paste0("  ", names(md5), "  ", md5),
    "",
    "Configuration:",
    paste0("  ", strsplit(yaml::as.yaml(cfg), "\n")[[1]])
  )
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  writeLines(lines, path)
  message("  wrote ", path)
  invisible(path)
}
