# Run all tests from the project root:  source("tests/run_tests.R")
testthat::test_dir("tests/testthat", reporter = testthat::ProgressReporter$new(show_praise = FALSE), stop_on_failure = TRUE)
