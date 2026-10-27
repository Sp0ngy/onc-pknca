# Source the project code (not a package) into the global environment, where PKNCA can find the
# registered imputation method by name.
project_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
source(file.path(project_root, "R", "functions.R"))
source(file.path(project_root, "R", "nca.R"))

test_cfg <- function(...) {
  cfg <- load_config(file.path(project_root, "config", "config.yml"))
  utils::modifyList(cfg, list(...))
}
