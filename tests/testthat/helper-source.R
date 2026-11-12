# Source the project code (not a package) into the global environment, where PKNCA can find the
# registered imputation method by name.
project_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
source(file.path(project_root, "R", "functions.R"))
source(file.path(project_root, "R", "nca.R"))

#' Project config with MBq/mL as concentration unit (the hand calculations use MBq/mL);
#' further overrides via `...`.
test_cfg <- function(...) {
  cfg <- load_config(file.path(project_root, "config", "config.yml"))
  cfg$units$conc <- "MBq/mL"
  utils::modifyList(cfg, list(...))
}

#' Run R/preprocess.R in a temporary copy of the project with config overrides and return
#' data/adnca.csv. Keeps the real data/ and output/ untouched.
run_preprocess_copy <- function(overrides) {
  tmp <- tempfile("proj")
  dir.create(tmp)
  for (d in c("R", "config", "data-raw")) {
    file.copy(file.path(project_root, d), tmp, recursive = TRUE)
  }
  cfg_path <- file.path(tmp, "config", "config.yml")
  cfg <- utils::modifyList(yaml::read_yaml(cfg_path), overrides)
  yaml::write_yaml(cfg, cfg_path)
  old <- setwd(tmp)
  on.exit({
    setwd(old)
    unlink(tmp, recursive = TRUE)
  })
  suppressMessages(sys.source(file.path("R", "preprocess.R"), envir = new.env()))
  utils::read.csv(file.path("data", "adnca.csv"), stringsAsFactors = FALSE)
}
