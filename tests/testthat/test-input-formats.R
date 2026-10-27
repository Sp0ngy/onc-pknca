test_that("unit factors", {
  expect_equal(unit_factor("kBq/mL", "MBq/mL"), 1e-3)
  expect_equal(unit_factor("MBq/mL", "kBq/mL"), 1e3)
  expect_equal(unit_factor("MBq/(h*kBq/mL)", "L/h"), 1)
  expect_equal(unit_factor("MBq/(h*MBq/mL)", "L/h"), 1e-3)
})

test_that("samples reported as BLQ in the input are treated as BLQ", {
  r <- apply_blq_rule(conc = c(0, 500, 200, 0), lloq = 0, rule = "pre_zero_post_missing",
                      blq_flag = c(TRUE, FALSE, FALSE, TRUE))
  expect_equal(r$conc, c(0, 500, 200, NA))
  expect_equal(r$blq, c(TRUE, FALSE, FALSE, TRUE))
})

test_that("urine with kBq/mL: Ae in MBq, fe in %", {
  cfg <- test_cfg()
  cfg$units$conc <- "kBq/mL"
  urine <- data.frame(USUBJID = "REF", AFRLT = c(0, 4), AEFRLT = c(4, 8), NFRLT = c(0, 4), NAEFRLT = c(4, 8),
                      AVAL = c(500, 200), VOLUME = c(200, 300))
  u <- run_urine_nca(urine, data.frame(USUBJID = "REF", DOSEA = 400, ADOSEDUR = 0), cfg)
  expect_equal(u$AE, c(100, 60))               # 500 kBq/mL x 200 mL = 100 MBq
  expect_equal(u$FE_CUM_PCT, c(25, 40))
})

test_that("CL and CLr are in L/h with kBq/mL", {
  cfg <- test_cfg()
  cfg$units$conc <- "kBq/mL"
  t <- c(0.5, 1, 2, 4, 8, 12, 24)
  c_mbq <- c(12, 10 * exp(-0.1 * (t[-1] - 1)))
  conc <- data.frame(USUBJID = "REF", PCSPEC = "PLASMA", AFRLT = t, NFRLT = t, AVAL = c_mbq * 1000)
  dose <- data.frame(USUBJID = "REF", DOSEA = 100, ADOSEDUR = 0)
  p_kbq <- run_systemic_nca(conc, dose, cfg)
  conc$AVAL <- c_mbq
  p_mbq <- run_systemic_nca(conc, dose, test_cfg())
  get <- function(p, x) p$PPSTRES[p$PPTESTCD == x]
  expect_equal(get(p_kbq, "cl.obs"), get(p_mbq, "cl.obs"))
  expect_equal(get(p_kbq, "vz.obs"), get(p_mbq, "vz.obs"))
  expect_equal(get(p_kbq, "aucinf.obs"), 1000 * get(p_mbq, "aucinf.obs"))

  urine_res <- data.frame(USUBJID = "REF", AEFRLT = 24, AE_CUM = 50, FE_CUM_PCT = 50)
  expect_equal(run_renal_clearance(transform(conc, AVAL = c_mbq * 1000), urine_res, dose, cfg)$CLR_L_PER_H,
               run_renal_clearance(conc, urine_res, dose, test_cfg())$CLR_L_PER_H)
})

test_that("both input formats give the same ADNCA (decay-corrected and effective)", {
  for (dc in c(TRUE, FALSE)) {
    counts <- run_preprocess_copy(list(input = list(format = "gamma_counts"),
                                       units = list(conc = "kBq/mL"),
                                       decay_correction = list(to_injection = dc)))
    concs <- run_preprocess_copy(list(input = list(format = "concentrations"),
                                      units = list(conc = "kBq/mL"),
                                      decay_correction = list(to_injection = dc)))
    expect_equal(nrow(counts), nrow(concs))
    key <- c("USUBJID", "PCSPEC", "NFRLT")
    m <- merge(counts[, c(key, "AVAL", "BLQFL", "AFRLT", "DOSEA")], concs[, c(key, "AVAL", "BLQFL", "AFRLT", "DOSEA")], by = key)
    expect_equal(nrow(m), nrow(counts))
    expect_equal(m$BLQFL.x, m$BLQFL.y)
    # concentrations file is rounded to 6 significant digits, times to 4 decimals, dose to 0.01 MBq
    expect_equal(m$AVAL.x, m$AVAL.y, tolerance = 1e-5)
    expect_equal(m$AFRLT.x, m$AFRLT.y, tolerance = 1e-4)
    expect_equal(m$DOSEA.x, m$DOSEA.y, tolerance = 1e-5)
    expect_true(all(m$AVAL.y[m$BLQFL.y == "N"] > 0))
  }
})
