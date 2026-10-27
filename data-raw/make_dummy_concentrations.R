# Convert the SYNTHETIC gamma counter dataset (data-raw/dummy_gamma_counts.csv + dummy_dosing.csv)
# into the "concentrations" input format: decay-corrected kBq/mL vs. time after injection (h).
# Both input formats therefore describe the same study, and tests check that they give the same NCA.
#
# Run from the project root (after data-raw/make_dummy_data.R): source("data-raw/make_dummy_concentrations.R")

source("R/functions.R")

hl_h <- 6.647 * 24
samples <- read.csv("data-raw/dummy_gamma_counts.csv", stringsAsFactors = FALSE, na.strings = "")
dosing <- read.csv("data-raw/dummy_dosing.csv", stringsAsFactors = FALSE, na.strings = "")

t_inj <- parse_datetime(dosing$INJECTION_DATETIME)
dosing$NET_INJECTED_MBQ <- round(net_injected_activity(
  dosing$SYRINGE_PRE_MBQ, parse_datetime(dosing$SYRINGE_PRE_DATETIME),
  dosing$SYRINGE_RESIDUAL_MBQ, parse_datetime(dosing$SYRINGE_RESIDUAL_DATETIME),
  t_inj, hl_h
), 2)

s <- merge(samples, data.frame(USUBJID = dosing$USUBJID, T_INJ = t_inj), by = "USUBJID")
t_sample <- parse_datetime(s$SAMPLE_DATETIME)
t_count <- parse_datetime(s$COUNT_DATETIME)
conc_count <- counts_to_mbq_per_ml(s$GROSS_COUNTS, s$COUNT_TIME_MIN, s$BACKGROUND_CPM,
                                   s$CAL_CPM_PER_BQ, s$ALIQUOT_VOLUME_ML, s$DILUTION_FACTOR)
conc_dc_kbq <- decay_correct(conc_count, t_count, s$T_INJ, hl_h) * 1000   # MBq/mL -> kBq/mL, to injection

out <- data.frame(
  STUDYID = s$STUDYID,
  USUBJID = s$USUBJID,
  MATRIX = s$MATRIX,
  SAMPLE_ID = s$SAMPLE_ID,
  NOMINAL_START_H = s$NOMINAL_START_H,
  NOMINAL_TIME_H = s$NOMINAL_TIME_H,
  START_TIME_H = round(ifelse(s$MATRIX == "URINE", hours_between(s$T_INJ, parse_datetime(s$SAMPLE_START_DATETIME)), NA), 4),
  TIME_H = round(hours_between(s$T_INJ, t_sample), 4),
  CONC = signif(conc_dc_kbq, 6),
  URINE_VOLUME_ML = s$URINE_VOLUME_ML,
  COMMENT = ""
)
# Lab-style BLQ reporting: below 0.1 kBq/mL as present in the sample -> "BLQ"
as_sampled <- decay_correct(conc_dc_kbq, t_measured = 0, t_reference = out$TIME_H, half_life_h = hl_h)
out$CONC[as_sampled < 0.1] <- "BLQ"
out <- out[order(out$USUBJID, out$MATRIX, out$NOMINAL_TIME_H), ]

write.csv(out, "data-raw/dummy_concentrations.csv", row.names = FALSE, na = "")
write.csv(dosing[, c("STUDYID", "USUBJID", "SEX", "AGE", "WEIGHT_KG", "NUCLIDE", "DRUG",
                     "NET_INJECTED_MBQ", "INFUSION_DURATION_MIN")],
          "data-raw/dummy_dosing_concentrations.csv", row.names = FALSE, na = "")
message("Wrote data-raw/dummy_concentrations.csv (", nrow(out), " rows) and data-raw/dummy_dosing_concentrations.csv")
