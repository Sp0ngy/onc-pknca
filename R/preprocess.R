# Preprocessing: raw gamma counter data -> activity concentrations (MBq/mL) -> ADNCA CSV for aNCA.
#
# Run from the project root:  source("R/preprocess.R")
# Inputs  : config/config.yml, raw sample + dosing CSVs (see templates/README.md)
# Outputs : data/adnca.csv                      ADNCA-format input for aNCA and R/run_nca.R
#           output/dose.csv                     net injected activity per subject
#           output/concentrations.csv           sample-level derivation (counts -> MBq/mL)
#           output/concentration_summary.csv    descriptive stats per matrix and nominal time
#           output/bp_ratio_individual.csv      whole blood-to-plasma ratio per subject and time
#           output/bp_ratio_summary.csv         descriptive stats of the ratio per nominal time
#           output/run_info_preprocess.txt      versions, checksums, configuration

source("R/functions.R")
source("R/io.R")

cfg <- load_config("config/config.yml")
hl_h <- cfg$nuclide$half_life_h
to_injection <- cfg$decay_correction$to_injection
message("Preprocessing - ", decay_label(to_injection), "; T1/2 phys = ", signif(hl_h, 6), " h")

read_input <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"), strip.white = TRUE)
}
samples <- read_input(cfg$input$samples)
dosing <- read_input(cfg$input$dosing)

# ---- input checks ------------------------------------------------------------------------------

required_samples <- c(
  "STUDYID", "USUBJID", "MATRIX", "SAMPLE_ID", "NOMINAL_START_H", "NOMINAL_TIME_H",
  "SAMPLE_START_DATETIME", "SAMPLE_DATETIME", "URINE_VOLUME_ML", "ALIQUOT_VOLUME_ML",
  "ALIQUOT_WEIGHT_G", "DILUTION_FACTOR", "COUNT_DATETIME", "COUNT_TIME_MIN", "GROSS_COUNTS",
  "BACKGROUND_CPM", "CAL_CPM_PER_BQ"
)
required_dosing <- c(
  "STUDYID", "USUBJID", "INJECTION_DATETIME", "INFUSION_DURATION_MIN",
  "SYRINGE_PRE_MBQ", "SYRINGE_PRE_DATETIME", "SYRINGE_RESIDUAL_MBQ", "SYRINGE_RESIDUAL_DATETIME"
)
missing_cols <- c(setdiff(required_samples, names(samples)), setdiff(required_dosing, names(dosing)))
if (length(missing_cols)) stop("Missing input columns: ", paste(missing_cols, collapse = ", "))

samples$MATRIX <- toupper(samples$MATRIX)
if (!all(samples$MATRIX %in% c("BLOOD", "PLASMA", "URINE"))) {
  stop("MATRIX must be BLOOD, PLASMA or URINE; found: ",
       paste(setdiff(unique(samples$MATRIX), c("BLOOD", "PLASMA", "URINE")), collapse = ", "))
}
if (anyDuplicated(dosing$USUBJID)) stop("Dosing file must have exactly one row per USUBJID")
no_dose <- setdiff(unique(samples$USUBJID), dosing$USUBJID)
if (length(no_dose)) stop("Subjects without dosing record: ", paste(no_dose, collapse = ", "))
is_urine <- samples$MATRIX == "URINE"
if (any(is.na(samples$URINE_VOLUME_ML[is_urine]) | is.na(samples$SAMPLE_START_DATETIME[is_urine]))) {
  stop("Urine samples need URINE_VOLUME_ML and SAMPLE_START_DATETIME")
}

# ---- dose: net injected activity at injection time ---------------------------------------------

dosing$T_INJ <- parse_datetime(dosing$INJECTION_DATETIME)
dosing$DOSEA <- net_injected_activity(
  pre_mbq = dosing$SYRINGE_PRE_MBQ,
  pre_time = parse_datetime(dosing$SYRINGE_PRE_DATETIME),
  residual_mbq = dosing$SYRINGE_RESIDUAL_MBQ,
  residual_time = parse_datetime(dosing$SYRINGE_RESIDUAL_DATETIME),
  injection_time = dosing$T_INJ,
  half_life_h = hl_h
)
if (any(dosing$DOSEA <= 0)) stop("Net injected activity <= 0 for: ", paste(dosing$USUBJID[dosing$DOSEA <= 0], collapse = ", "))

# ---- samples: counts -> MBq/mL -> decay correction ---------------------------------------------

s <- merge(samples, dosing[, c("USUBJID", "T_INJ", "DOSEA", "INFUSION_DURATION_MIN")], by = "USUBJID")
t_sample <- parse_datetime(s$SAMPLE_DATETIME)        # blood/plasma: sampling; urine: end of collection
t_start <- parse_datetime(s$SAMPLE_START_DATETIME)   # urine only
t_count <- parse_datetime(s$COUNT_DATETIME)
if (any(t_count < t_sample)) stop("COUNT_DATETIME before SAMPLE_DATETIME for: ", paste(s$SAMPLE_ID[t_count < t_sample], collapse = ", "))

density <- unlist(cfg$density_g_per_ml)[s$MATRIX]
s$ALIQUOT_ML <- aliquot_volume_ml(s$ALIQUOT_VOLUME_ML, s$ALIQUOT_WEIGHT_G, density)
s$NET_CPM <- net_cpm(s$GROSS_COUNTS, s$COUNT_TIME_MIN, s$BACKGROUND_CPM)
s$CONC_AT_COUNT <- counts_to_mbq_per_ml(s$GROSS_COUNTS, s$COUNT_TIME_MIN, s$BACKGROUND_CPM,
                                        s$CAL_CPM_PER_BQ, s$ALIQUOT_ML, s$DILUTION_FACTOR)
# Always: back to the time the sample left the body (decay in the tube is an artefact).
s$CONC_AT_SAMPLING <- decay_correct(s$CONC_AT_COUNT, t_count, t_sample, hl_h)
# Optional: back to injection time. Exact for urine too, because activity keeps decaying at the
# same rate in the bladder/collection container as in the body.
s$CONC_REPORTED <- if (to_injection) decay_correct(s$CONC_AT_SAMPLING, t_sample, s$T_INJ, hl_h) else s$CONC_AT_SAMPLING

s$AFRLT <- ifelse(s$MATRIX == "URINE", hours_between(s$T_INJ, t_start), hours_between(s$T_INJ, t_sample))
s$AEFRLT <- ifelse(s$MATRIX == "URINE", hours_between(s$T_INJ, t_sample), NA_real_)
s$NFRLT <- ifelse(s$MATRIX == "URINE", s$NOMINAL_START_H, s$NOMINAL_TIME_H)
s$NAEFRLT <- ifelse(s$MATRIX == "URINE", s$NOMINAL_TIME_H, NA_real_)

# ---- BLQ ---------------------------------------------------------------------------------------

lloq <- unlist(cfg$blq$lloq_mbq_per_ml)
s$LLOQ <- unname(lloq[s$MATRIX])
s <- s[order(s$USUBJID, s$MATRIX, s$AFRLT), ]
s$AVAL <- NA_real_
s$BLQFL <- NA_character_
for (idx in split(seq_len(nrow(s)), list(s$USUBJID, s$MATRIX), drop = TRUE)) {
  rule <- if (s$MATRIX[idx[1]] == "URINE") cfg$blq$rule_urine else cfg$blq$rule
  r <- apply_blq_rule(s$CONC_REPORTED[idx], s$LLOQ[idx], rule, conc_for_blq = s$CONC_AT_SAMPLING[idx])
  s$AVAL[idx] <- r$conc
  s$BLQFL[idx] <- ifelse(r$blq, "Y", "N")
}

# ---- ADNCA -------------------------------------------------------------------------------------

demog <- intersect(c("SEX", "AGE", "WEIGHT_KG"), names(dosing))
s <- merge(s, dosing[, c("USUBJID", demog), drop = FALSE], by = "USUBJID")
s <- s[order(s$USUBJID, s$MATRIX, s$AFRLT), ]

adnca <- data.frame(
  STUDYID = s$STUDYID,
  USUBJID = s$USUBJID,
  PARAM = cfg$study$param,
  PARAMCD = cfg$study$paramcd,
  PCSPEC = s$MATRIX,
  ATPTREF = "DOSE 1",
  AVAL = s$AVAL,
  AVALU = cfg$units$conc,
  AFRLT = s$AFRLT,
  ARRLT = s$AFRLT,                      # single dose: relative to first = relative to most recent dose
  NFRLT = s$NFRLT,
  NRRLT = s$NFRLT,
  AEFRLT = s$AEFRLT,                    # urine: end of collection interval (AFRLT = start)
  NAEFRLT = s$NAEFRLT,
  RRLTU = cfg$units$time,
  ROUTE = "INTRAVENOUS",
  DOSETRT = cfg$study$drug,
  DOSEA = s$DOSEA,
  DOSEU = cfg$units$dose,
  ADOSEDUR = s$INFUSION_DURATION_MIN / 60,
  VOLUME = ifelse(s$MATRIX == "URINE", s$URINE_VOLUME_ML, NA_real_),
  VOLUMEU = ifelse(s$MATRIX == "URINE", cfg$units$volume, NA_character_),
  LLOQ = s$LLOQ,
  BLQFL = s$BLQFL,
  DECAYCFL = if (to_injection) "Y" else "N",
  NUCLIDE = cfg$nuclide$name,
  PHYSHL = cfg$nuclide$half_life_h,
  SAMPLEID = s$SAMPLE_ID,
  stringsAsFactors = FALSE
)
if ("SEX" %in% demog) adnca$SEX <- s$SEX
if ("AGE" %in% demog) adnca$AGE <- s$AGE
if ("WEIGHT_KG" %in% demog) {
  adnca$WEIGHT <- s$WEIGHT_KG
  adnca$WEIGHTU <- "kg"
}

dir.create("data", showWarnings = FALSE)
utils::write.csv(adnca, "data/adnca.csv", row.names = FALSE, na = "")
message("  wrote data/adnca.csv (", nrow(adnca), " rows)")

# ---- report tables -----------------------------------------------------------------------------

write_output(
  data.frame(
    USUBJID = dosing$USUBJID, INJECTION_DATETIME = dosing$INJECTION_DATETIME,
    SYRINGE_PRE_MBQ = dosing$SYRINGE_PRE_MBQ, SYRINGE_RESIDUAL_MBQ = dosing$SYRINGE_RESIDUAL_MBQ,
    NET_INJECTED_MBQ = dosing$DOSEA
  ),
  "output/dose.csv", cfg
)

write_output(
  s[, c("USUBJID", "MATRIX", "SAMPLE_ID", "NFRLT", "NAEFRLT", "AFRLT", "AEFRLT", "SAMPLE_DATETIME",
        "COUNT_DATETIME", "GROSS_COUNTS", "COUNT_TIME_MIN", "BACKGROUND_CPM", "NET_CPM", "CAL_CPM_PER_BQ",
        "ALIQUOT_ML", "DILUTION_FACTOR", "URINE_VOLUME_ML", "CONC_AT_COUNT", "CONC_AT_SAMPLING",
        "CONC_REPORTED", "LLOQ", "BLQFL", "AVAL")],
  "output/concentrations.csv", cfg
)

conc_bp <- adnca[adnca$PCSPEC != "URINE", ]
write_output(summarise_by(conc_bp[!is.na(conc_bp$AVAL), ], c("PCSPEC", "NFRLT"), "AVAL"),
             "output/concentration_summary.csv", cfg)

bp <- bp_ratio(conc_bp)
write_output(bp, "output/bp_ratio_individual.csv", cfg)
write_output(summarise_by(bp[!is.na(bp$BP_RATIO), ], "NFRLT", "BP_RATIO"), "output/bp_ratio_summary.csv", cfg)

write_run_info("output/run_info_preprocess.txt", cfg, c(cfg$input$samples, cfg$input$dosing, "config/config.yml"),
               step = "R/preprocess.R")
message("Preprocessing done.")
