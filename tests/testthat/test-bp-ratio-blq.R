test_that("blood-to-plasma ratio is calculated per subject and nominal time", {
  conc <- data.frame(
    USUBJID = rep(c("A", "B"), each = 4),
    PCSPEC = rep(c("BLOOD", "BLOOD", "PLASMA", "PLASMA"), 2),
    NFRLT = rep(c(1, 24), 4),
    AFRLT = rep(c(1.02, 23.9), 4),
    AVAL = c(0.6, 0.07, 1.0, 0.1, 0.8, 0, 1.0, 0.2)
  )
  r <- bp_ratio(conc)
  expect_equal(nrow(r), 4)
  expect_equal(r$BP_RATIO[r$USUBJID == "A"], c(0.6, 0.7))
  expect_equal(r$BP_RATIO[r$USUBJID == "B" & r$NFRLT == 1], 0.8)
  # blood BLQ (0) -> no ratio
  expect_true(is.na(r$BP_RATIO[r$USUBJID == "B" & r$NFRLT == 24]))
})

test_that("BLQ rules are applied relative to the first quantifiable value", {
  conc <- c(0.00001, 0.5, 0.2, 0.00002, 0.1, 0.00003)
  lloq <- 0.0001
  r <- apply_blq_rule(conc, lloq, "pre_zero_post_missing")
  expect_equal(r$conc, c(0, 0.5, 0.2, NA, 0.1, NA))
  expect_equal(r$blq, c(TRUE, FALSE, FALSE, TRUE, FALSE, TRUE))
  expect_equal(apply_blq_rule(conc, lloq, "zero")$conc, c(0, 0.5, 0.2, 0, 0.1, 0))
  expect_equal(apply_blq_rule(conc, lloq, "missing")$conc, c(NA, 0.5, 0.2, NA, 0.1, NA))
  expect_equal(apply_blq_rule(conc, lloq, "half_lloq")$conc, c(0, 0.5, 0.2, 5e-5, 0.1, 5e-5))
})

test_that("BLQ is judged on the as-sampled value, not the decay-corrected one", {
  # decay-corrected value is above LLOQ, the value present in the sample was below
  r <- apply_blq_rule(conc = c(0.5, 0.00015), lloq = 0.0001, rule = "pre_zero_post_missing",
                      conc_for_blq = c(0.4, 0.00008))
  expect_equal(r$conc, c(0.5, NA))
})

test_that("descriptive statistics", {
  d <- describe(c(1, 2, 4))
  expect_equal(d$N, 3)
  expect_equal(d$MEAN, 7 / 3)
  expect_equal(d$GEOMEAN, 2)
  expect_equal(d$MEDIAN, 2)
  expect_equal(d$GEOCV_PCT, 100 * sqrt(exp(stats::sd(log(c(1, 2, 4)))^2) - 1))
})
