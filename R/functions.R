# Core calculation functions for radiopharmaceutical PK (gamma counter, total radioactivity).
# Sourced by R/preprocess.R, R/run_nca.R and tests/testthat. Pure functions only, no file I/O
# except load_config().

# ---- configuration -----------------------------------------------------------------------------

TIME_UNIT_TO_H <- c(s = 1 / 3600, min = 1 / 60, h = 1, d = 24)
BLQ_RULES <- c("pre_zero_post_missing", "zero", "missing", "half_lloq")

load_config <- function(path = "config/config.yml") {
  cfg <- yaml::read_yaml(path)
  unit <- cfg$nuclide$half_life_unit
  if (!unit %in% names(TIME_UNIT_TO_H)) {
    stop("nuclide$half_life_unit must be one of: ", paste(names(TIME_UNIT_TO_H), collapse = ", "))
  }
  cfg$nuclide$half_life_h <- cfg$nuclide$half_life * TIME_UNIT_TO_H[[unit]]
  stopifnot(
    is.logical(cfg$decay_correction$to_injection),
    cfg$blq$rule %in% BLQ_RULES,
    cfg$blq$rule_urine %in% BLQ_RULES,
    cfg$nca$c0_imputation %in% c("auto", "start_logslope", "start_conc0", "none")
  )
  cfg
}

#' Human-readable label of the decay-correction mode, written into every output table.
decay_label <- function(to_injection) {
  if (to_injection) {
    "Decay-corrected to injection time (biological half-life)"
  } else {
    "Not decay-corrected to injection time (effective half-life)"
  }
}

# ---- time and decay ----------------------------------------------------------------------------

#' Parse "YYYY-MM-DD HH:MM[:SS]" as UTC (avoids daylight-saving jumps in time differences).
parse_datetime <- function(x) {
  x <- trimws(as.character(x))
  x[x == ""] <- NA
  out <- as.POSIXct(x, tz = "UTC", tryFormats = c("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"))
  out
}

hours_between <- function(from, to) {
  as.numeric(difftime(to, from, units = "hours"))
}

decay_constant <- function(half_life_h) {
  log(2) / half_life_h
}

#' Decay-correct an activity measured at `t_measured` to reference time `t_reference`.
#'
#' A(t_ref) = A(t_meas) * exp(lambda * (t_meas - t_ref)). Times are POSIXct or numeric hours.
#' If the reference time is earlier than the measurement, the activity increases.
decay_correct <- function(activity, t_measured, t_reference, half_life_h) {
  dt_h <- if (inherits(t_measured, "POSIXct")) {
    hours_between(t_reference, t_measured)
  } else {
    t_measured - t_reference
  }
  activity * exp(decay_constant(half_life_h) * dt_h)
}

#' Net injected activity at injection time (MBq): syringe activity before injection minus the
#' residual activity measured afterwards, both decay-corrected to the injection time.
net_injected_activity <- function(pre_mbq, pre_time, residual_mbq, residual_time,
                                  injection_time, half_life_h) {
  residual_mbq[is.na(residual_mbq)] <- 0
  residual_time[is.na(residual_time)] <- injection_time[is.na(residual_time)]
  decay_correct(pre_mbq, pre_time, injection_time, half_life_h) -
    decay_correct(residual_mbq, residual_time, injection_time, half_life_h)
}

# ---- gamma counter -----------------------------------------------------------------------------

#' Net count rate (cpm) = gross counts / counting time - background (cpm).
net_cpm <- function(gross_counts, count_time_min, background_cpm) {
  gross_counts / count_time_min - background_cpm
}

#' Activity (Bq) from net cpm with a counter calibration factor in cpm per Bq
#' (i.e. 60 * counting efficiency for the nuclide/energy window).
cpm_to_bq <- function(net_cpm, cal_cpm_per_bq) {
  net_cpm / cal_cpm_per_bq
}

#' Aliquot volume in mL; falls back to weight / density when no volume was recorded.
aliquot_volume_ml <- function(volume_ml, weight_g, density_g_per_ml) {
  ifelse(is.na(volume_ml), weight_g / density_g_per_ml, volume_ml)
}

#' Activity concentration (MBq/mL) at counting time from raw counter data.
#' `dilution_factor` refers to the original sample (e.g. 20 for a 1:20 pre-dilution).
counts_to_mbq_per_ml <- function(gross_counts, count_time_min, background_cpm,
                                 cal_cpm_per_bq, volume_ml, dilution_factor = 1) {
  dilution_factor[is.na(dilution_factor)] <- 1
  bq <- cpm_to_bq(net_cpm(gross_counts, count_time_min, background_cpm), cal_cpm_per_bq)
  bq * dilution_factor / volume_ml / 1e6
}

# ---- BLQ handling ------------------------------------------------------------------------------

#' Apply a BLQ rule to one concentration-time profile (one subject, one matrix).
#'
#' @param conc concentrations ordered by time.
#' @param lloq LLOQ (scalar or per sample).
#' @param conc_for_blq values compared against the LLOQ (default `conc`); used to judge BLQ on
#'   the as-sampled activity while `conc` may be decay-corrected to injection.
#' @return list(conc = processed concentrations, blq = logical BLQ flag).
apply_blq_rule <- function(conc, lloq, rule, conc_for_blq = conc) {
  rule <- match.arg(rule, BLQ_RULES)
  blq <- !is.na(conc_for_blq) & conc_for_blq < lloq
  quant <- which(!blq & !is.na(conc))
  before_first <- if (length(quant)) seq_along(conc) < min(quant) else rep(TRUE, length(conc))
  lloq <- rep_len(lloq, length(conc))
  out <- conc
  out[blq] <- switch(rule,
    zero = 0,
    missing = NA_real_,
    pre_zero_post_missing = ifelse(before_first[blq], 0, NA_real_),
    half_lloq = ifelse(before_first[blq], 0, lloq[blq] / 2)
  )
  list(conc = out, blq = blq)
}

# ---- blood-to-plasma ratio ---------------------------------------------------------------------

#' Whole blood-to-plasma ratio per subject and nominal time.
#'
#' @param conc data.frame with USUBJID, PCSPEC (BLOOD/PLASMA), NFRLT, AFRLT, AVAL.
#'   Blood and plasma are matched on USUBJID + NFRLT (plasma separated from the same draw).
#'   Ratios are only calculated where both values are quantifiable (> 0).
bp_ratio <- function(conc) {
  key <- c("USUBJID", "NFRLT")
  b <- conc[conc$PCSPEC == "BLOOD", c(key, "AFRLT", "AVAL")]
  p <- conc[conc$PCSPEC == "PLASMA", c(key, "AVAL")]
  names(b)[names(b) == "AVAL"] <- "BLOOD"
  names(p)[names(p) == "AVAL"] <- "PLASMA"
  m <- merge(b, p, by = key, all = TRUE)
  ok <- !is.na(m$BLOOD) & !is.na(m$PLASMA) & m$BLOOD > 0 & m$PLASMA > 0
  m$BP_RATIO <- ifelse(ok, m$BLOOD / m$PLASMA, NA_real_)
  m[order(m$USUBJID, m$NFRLT), ]
}

# ---- descriptive statistics --------------------------------------------------------------------

#' Descriptive statistics (n, mean, SD, CV%, geometric mean, geometric CV%, median, min, max).
#' Geometric statistics use positive values only.
describe <- function(x) {
  x <- x[!is.na(x)]
  xp <- x[x > 0]
  n <- length(x)
  sd_x <- if (n > 1) stats::sd(x) else NA_real_
  sd_log <- if (length(xp) > 1) stats::sd(log(xp)) else NA_real_
  data.frame(
    N = n,
    MEAN = if (n) mean(x) else NA_real_,
    SD = sd_x,
    CV_PCT = if (n) 100 * sd_x / mean(x) else NA_real_,
    GEOMEAN = if (length(xp)) exp(mean(log(xp))) else NA_real_,
    GEOCV_PCT = 100 * sqrt(exp(sd_log^2) - 1),
    MEDIAN = if (n) stats::median(x) else NA_real_,
    MIN = if (n) min(x) else NA_real_,
    MAX = if (n) max(x) else NA_real_
  )
}

#' Apply describe() to `value_col` within each combination of `by` columns.
summarise_by <- function(df, by, value_col) {
  groups <- split(df, df[by], drop = TRUE)
  rows <- lapply(groups, function(g) cbind(g[1, by, drop = FALSE], describe(g[[value_col]])))
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out[do.call(order, out[by]), ]
}
