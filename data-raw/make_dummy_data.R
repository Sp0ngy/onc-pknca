# Generate a SYNTHETIC radiopharmaceutical PK dataset in the raw gamma-counter template format.
#
# Scenario: single IV bolus of a Lu-177 radioligand (~7.4 GBq), 8 subjects, whole blood, plasma
# (from the same draw) and urine (0-4, 4-8, 8-24, 24-48, 48-72, 72-96 h collections).
# Ground truth (decay-corrected) model:
#   blood   C_b(t) = Dose / V_b * sum_i f_i * exp(-k_i t)   (tri-exponential)
#   plasma  C_p(t) = C_b(t) / BP(t),  BP(t) = BP0 + dBP * (1 - exp(-t / 48))
#   urine   dAe/dt = CLr * C_p(t),  CLr chosen so that fe(0-96 h) ~ 45-70 %
# "Measured" values: physical decay to sampling time and to counting time, 3 % assay noise,
# Poisson counting statistics, background. No real study data is used.
#
# Run from the project root: source("data-raw/make_dummy_data.R")

set.seed(20261027)

half_life_h <- 6.647 * 24
lambda_p <- log(2) / half_life_h
n_subj <- 8
studyid <- "ONC-DUMMY-001"
fmt <- function(t) format(t, "%Y-%m-%d %H:%M:%S", tz = "UTC")
round_min <- function(t) as.POSIXct(round(as.numeric(t) / 60) * 60, origin = "1970-01-01", tz = "UTC")

nominal_h <- c(0, 0.0833, 0.25, 0.5, 1, 2, 4, 8, 24, 48, 72, 120, 168, 336)
urine_int <- data.frame(start = c(0, 4, 8, 24, 48, 72), end = c(4, 8, 24, 48, 72, 96))

aliquot_ml <- c(BLOOD = 0.2, PLASMA = 0.2, URINE = 1.0)
dilution <- c(BLOOD = 1, PLASMA = 1, URINE = 20)   # urine pre-diluted 1:20 to stay in the counter's linear range
cal_cpm_per_bq <- 4.8        # ~8 % counting efficiency in the 208 keV window
count_time_min <- 1
background_cpm <- 30

lnorm_iiv <- function(typical, cv) typical * exp(rnorm(1, 0, cv))

dosing <- list()
samples <- list()

for (i in seq_len(n_subj)) {
  usubjid <- sprintf("%s-%03d", studyid, i)
  t_inj <- as.POSIXct("2026-03-02 09:00:00", tz = "UTC") + (i - 1) * 7 * 86400 + round(runif(1, 0, 90)) * 60

  # --- dose: syringe measured in dose calibrator before and after injection
  t_pre <- t_inj - round(runif(1, 10, 25)) * 60
  t_res <- t_inj + round(runif(1, 5, 15)) * 60
  a_inj_target <- runif(1, 7100, 7600)
  residual_at_inj <- runif(1, 40, 180)
  pre_mbq <- (a_inj_target + residual_at_inj) * exp(-lambda_p * as.numeric(difftime(t_pre, t_inj, units = "hours")))
  res_mbq <- residual_at_inj * exp(-lambda_p * as.numeric(difftime(t_res, t_inj, units = "hours")))
  dose <- a_inj_target                                  # net injected activity at injection time

  sex <- sample(c("M", "F"), 1, prob = c(0.7, 0.3))
  dosing[[i]] <- data.frame(
    STUDYID = studyid, USUBJID = usubjid, SEX = sex, AGE = round(runif(1, 52, 79)),
    WEIGHT_KG = round(if (sex == "M") rnorm(1, 84, 10) else rnorm(1, 69, 8), 1),
    NUCLIDE = "Lu-177", DRUG = "[177Lu]Lu-DUMMY",
    INJECTION_DATETIME = fmt(t_inj), INFUSION_DURATION_MIN = 0,
    SYRINGE_PRE_MBQ = round(pre_mbq, 1), SYRINGE_PRE_DATETIME = fmt(t_pre),
    SYRINGE_RESIDUAL_MBQ = round(res_mbq, 2), SYRINGE_RESIDUAL_DATETIME = fmt(t_res)
  )

  # --- individual PK parameters
  v_b <- lnorm_iiv(5000, 0.15)                          # mL
  f <- c(0.60, 0.30, 0.10) * exp(rnorm(3, 0, 0.1)); f <- f / sum(f)
  k <- log(2) / c(lnorm_iiv(0.25, 0.2), lnorm_iiv(2.5, 0.2), lnorm_iiv(30, 0.25))
  bp0 <- runif(1, 0.58, 0.66); dbp <- runif(1, 0.08, 0.2)
  c_blood <- function(t) dose / v_b * colSums(f * exp(-outer(k, t)))
  bp <- function(t) bp0 + dbp * (1 - exp(-t / 48))
  c_plasma <- function(t) c_blood(t) / bp(t)
  fe_target <- runif(1, 0.45, 0.70)
  clr <- fe_target * dose / integrate(c_plasma, 0, 96, subdivisions = 1000)$value   # mL/h

  # --- blood + plasma: actual sampling times, counted in batches 1-4 days later
  t_actual <- round_min(t_inj + nominal_h * 3600 + c(-20, rnorm(length(nominal_h) - 1, 0, pmax(1, nominal_h[-1] * 0.02))) * 60)
  for (j in seq_along(nominal_h)) {
    t_h <- as.numeric(difftime(t_actual[j], t_inj, units = "hours"))
    t_count <- round_min(t_actual[j] + runif(1, 24, 96) * 3600)
    for (mat in c("BLOOD", "PLASMA")) {
      true_dc <- if (t_h < 0) 0 else if (mat == "BLOOD") c_blood(t_h) else c_plasma(t_h)   # MBq/mL
      phys_at_count <- true_dc * exp(-lambda_p * as.numeric(difftime(t_count, t_inj, units = "hours")))
      bq <- phys_at_count * 1e6 * aliquot_ml[[mat]] / dilution[[mat]] * exp(rnorm(1, 0, 0.03))
      gross <- rpois(1, (bq * cal_cpm_per_bq + background_cpm) * count_time_min)
      samples[[length(samples) + 1]] <- data.frame(
        STUDYID = studyid, USUBJID = usubjid, MATRIX = mat,
        SAMPLE_ID = sprintf("%s-%s-%02d", sub(".*-", "S", usubjid), substr(mat, 1, 1), j),
        NOMINAL_START_H = NA, NOMINAL_TIME_H = nominal_h[j],
        SAMPLE_START_DATETIME = "", SAMPLE_DATETIME = fmt(t_actual[j]),
        URINE_VOLUME_ML = NA, ALIQUOT_VOLUME_ML = aliquot_ml[[mat]], ALIQUOT_WEIGHT_G = NA, DILUTION_FACTOR = dilution[[mat]],
        COUNT_DATETIME = fmt(t_count), COUNT_TIME_MIN = count_time_min, GROSS_COUNTS = gross,
        BACKGROUND_CPM = background_cpm, CAL_CPM_PER_BQ = cal_cpm_per_bq, COMMENT = ""
      )
    }
  }

  # --- urine collections: activity in the jug decays until the end of collection
  t_end_prev <- t_inj
  for (j in seq_len(nrow(urine_int))) {
    t_start <- t_end_prev
    t_end <- round_min(t_inj + urine_int$end[j] * 3600 + rnorm(1, 0, 10) * 60)
    s_h <- as.numeric(difftime(t_start, t_inj, units = "hours"))
    e_h <- as.numeric(difftime(t_end, t_inj, units = "hours"))
    ae_dc <- clr * integrate(c_plasma, s_h, e_h, subdivisions = 1000)$value             # MBq
    vol <- round(runif(1, 25, 60) * (e_h - s_h))                                         # mL, 25-60 mL/h urine flow
    t_count <- round_min(t_end + runif(1, 24, 96) * 3600)
    phys_conc_at_count <- ae_dc / vol * exp(-lambda_p * as.numeric(difftime(t_count, t_inj, units = "hours")))
    bq <- phys_conc_at_count * 1e6 * aliquot_ml[["URINE"]] / dilution[["URINE"]] * exp(rnorm(1, 0, 0.03))
    gross <- rpois(1, (bq * cal_cpm_per_bq + background_cpm) * count_time_min)
    samples[[length(samples) + 1]] <- data.frame(
      STUDYID = studyid, USUBJID = usubjid, MATRIX = "URINE",
      SAMPLE_ID = sprintf("%s-U-%02d", sub(".*-", "S", usubjid), j),
      NOMINAL_START_H = urine_int$start[j], NOMINAL_TIME_H = urine_int$end[j],
      SAMPLE_START_DATETIME = fmt(t_start), SAMPLE_DATETIME = fmt(t_end),
      URINE_VOLUME_ML = vol, ALIQUOT_VOLUME_ML = aliquot_ml[["URINE"]], ALIQUOT_WEIGHT_G = NA, DILUTION_FACTOR = dilution[["URINE"]],
      COUNT_DATETIME = fmt(t_count), COUNT_TIME_MIN = count_time_min, GROSS_COUNTS = gross,
      BACKGROUND_CPM = background_cpm, CAL_CPM_PER_BQ = cal_cpm_per_bq, COMMENT = ""
    )
    t_end_prev <- t_end
  }
}

dosing <- do.call(rbind, dosing)
samples <- do.call(rbind, samples)
samples <- samples[order(samples$USUBJID, samples$MATRIX, samples$NOMINAL_TIME_H), ]

write.csv(dosing, "data-raw/dummy_dosing.csv", row.names = FALSE, na = "")
write.csv(samples, "data-raw/dummy_gamma_counts.csv", row.names = FALSE, na = "")
message("Wrote ", nrow(samples), " samples for ", n_subj, " subjects to data-raw/")
