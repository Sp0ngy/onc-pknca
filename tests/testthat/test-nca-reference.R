# Hand-calculated NCA reference subject (IV bolus, 100 MBq).
# Data: C(0.5 h) = 12, then mono-exponential C(t) = 10 * exp(-0.1 * (t - 1)) for t >= 1 h.
# - Cmax/Tmax are observed: 12 MBq/mL at 0.5 h (never the imputed C0).
# - C0 by log-linear back-extrapolation of the first two points: 12 * (12 / 10) = 14.4.
# - lambda_z: all 6 points after Tmax lie exactly on the exponential -> lambda_z = 0.1 1/h,
#   PKNCA picks the largest number of points with equal adj. R2 -> 6 points from t = 1 h.
# - AUC (lin-up/log-down; all segments decreasing -> log trapezoid (C1 - C2) * dt / ln(C1 / C2)).

ref_times <- c(0.5, 1, 2, 4, 8, 12, 24)
ref_conc <- c(12, 10 * exp(-0.1 * (ref_times[-1] - 1)))
ref_dose <- 100

hand <- local({
  log_trap <- function(c1, c2, dt) (c1 - c2) * dt / log(c1 / c2)
  c0 <- 12 * 12 / 10
  t_all <- c(0, ref_times)
  c_all <- c(c0, ref_conc)
  auclast <- sum(log_trap(head(c_all, -1), tail(c_all, -1), diff(t_all)))
  clast <- tail(ref_conc, 1)
  lz <- 0.1
  aucinf <- auclast + clast / lz
  cl <- ref_dose / aucinf                     # mL/h
  list(
    c0 = c0, auclast = auclast, aucinf = aucinf, lz = lz, half_life = log(2) / lz,
    aucpext = 100 * (clast / lz) / aucinf,
    cl_l_h = cl / 1000, vz_l = cl / lz / 1000
  )
})

run_reference <- function(cfg = test_cfg()) {
  conc <- data.frame(USUBJID = "REF", PCSPEC = "PLASMA", AFRLT = ref_times, NFRLT = ref_times, AVAL = ref_conc)
  dose <- data.frame(USUBJID = "REF", DOSEA = ref_dose, ADOSEDUR = 0)
  res <- run_systemic_nca(conc, dose, cfg)
  stats::setNames(res$PPSTRES, res$PPTESTCD)
}

test_that("hand-calculated values are what we think they are", {
  # sanity check of the reference itself: the log trapezoid is exact for an exponential
  expect_equal(hand$c0, 14.4)
  expect_equal(hand$auclast - (2.4 + 2) * 0.5 / log(1.2), (10 - 10 * exp(-2.3)) / 0.1)
})

test_that("PKNCA reproduces the hand-calculated reference subject", {
  p <- run_reference()
  expect_equal(p[["cmax"]], 12)
  expect_equal(p[["tmax"]], 0.5)
  expect_equal(p[["tlast"]], 24)
  expect_equal(p[["lambda.z"]], hand$lz, tolerance = 1e-10)
  expect_equal(p[["lambda.z.n.points"]], 6)
  expect_equal(p[["lambda.z.time.first"]], 1)
  expect_equal(p[["half.life"]], hand$half_life, tolerance = 1e-10)
  expect_equal(p[["auclast"]], hand$auclast, tolerance = 1e-10)
  expect_equal(p[["aucinf.obs"]], hand$aucinf, tolerance = 1e-10)
  expect_equal(p[["aucpext.obs"]], hand$aucpext, tolerance = 1e-10)
  expect_equal(p[["cl.obs"]], hand$cl_l_h, tolerance = 1e-10)
  expect_equal(p[["vz.obs"]], hand$vz_l, tolerance = 1e-10)
})

test_that("start_logslope imputation adds C0 = 14.4 at t = 0", {
  d <- PKNCA_impute_method_start_logslope(ref_conc, ref_times, start = 0, end = Inf)
  expect_equal(d$time[1], 0)
  expect_equal(d$conc[1], 14.4)
})

test_that("urine: Ae per interval, cumulative Ae/fe and the PKNCA cross-check", {
  urine <- data.frame(
    USUBJID = "REF", AFRLT = c(0, 4, 8), AEFRLT = c(4, 8, 24), NFRLT = c(0, 4, 8), NAEFRLT = c(4, 8, 24),
    AVAL = c(0.5, 0.2, 0.05), VOLUME = c(200, 300, 800)
  )
  dose <- data.frame(USUBJID = "REF", DOSEA = 400, ADOSEDUR = 0)
  u <- run_urine_nca(urine, dose, test_cfg())
  expect_equal(u$AE, c(100, 60, 40))
  expect_equal(u$FE_PCT, c(25, 15, 10))
  expect_equal(u$AE_CUM, c(100, 160, 200))
  expect_equal(u$FE_CUM_PCT, c(25, 40, 50))
})

test_that("renal clearance = Ae(0-T) / plasma AUC(0-T)", {
  plasma <- data.frame(USUBJID = "REF", PCSPEC = "PLASMA", AFRLT = ref_times, NFRLT = ref_times, AVAL = ref_conc)
  urine_res <- data.frame(USUBJID = "REF", AEFRLT = 24, AE_CUM = 50, FE_CUM_PCT = 50)
  dose <- data.frame(USUBJID = "REF", DOSEA = ref_dose, ADOSEDUR = 0)
  clr <- run_renal_clearance(plasma, urine_res, dose, test_cfg())
  expect_equal(clr$AUC_PLASMA_0_T, hand$auclast, tolerance = 1e-10)
  expect_equal(clr$CLR_L_PER_H, 50 / hand$auclast / 1000, tolerance = 1e-10)

  # T between two samples (20 h): log interpolation is exact on the exponential
  auc_0_20 <- hand$auclast - (10 * exp(-1.9) - 10 * exp(-2.3)) / 0.1
  expect_equal(plasma_auc_0_t(ref_times, ref_conc, 20, test_cfg(), 0), auc_0_20, tolerance = 1e-10)
})
