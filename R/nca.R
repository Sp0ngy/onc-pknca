# NCA functions on top of PKNCA. Sourced by R/run_nca.R and tests/testthat.
# Expects R/functions.R to be sourced as well.

SYSTEMIC_PARAMS <- c(
  "cmax", "tmax", "tlast", "clast.obs", "auclast", "aucinf.obs", "aucpext.obs",
  "lambda.z", "half.life", "r.squared", "adj.r.squared", "lambda.z.n.points",
  "lambda.z.time.first", "span.ratio", "cl.obs", "vz.obs"
)
# Parameters calculated with the imputed concentration at dose time (C0); all others use the
# observed data only, so Cmax/Tmax are never the imputed C0.
AUC_PARAMS <- c("auclast", "aucinf.obs", "aucpext.obs", "cl.obs", "vz.obs")

PARAM_LABELS <- c(
  cmax = "Cmax", tmax = "Tmax", tlast = "Tlast", clast.obs = "Clast", auclast = "AUC0-t",
  aucinf.obs = "AUC0-inf", aucpext.obs = "AUC %extrap", lambda.z = "lambda_z (kel)",
  half.life = "t1/2", r.squared = "R2 (lambda_z)", adj.r.squared = "adj. R2 (lambda_z)",
  lambda.z.n.points = "n points (lambda_z)", lambda.z.time.first = "lambda_z start time",
  span.ratio = "span ratio", cl.obs = "CL", vz.obs = "Vz", ae = "Ae (cumulative)",
  fe = "fe (cumulative)", aucint.last = "AUC0-T (plasma, T = end of urine collection)"
)

#' Log-linear back-extrapolation of C0 for IV bolus (C0 = C1 * (C1/C2)^(t1/(t2-t1))),
#' via PKNCA::pk.calc.c0(method = "logslope"). PKNCA 0.12.1 has no built-in "start_logslope"
#' imputation, so it is registered here (same approach as aNCA). Must live in the global
#' environment for PKNCA to find it by name.
PKNCA_impute_method_start_logslope <- function(conc, time, start, end, ..., options = list()) {
  d <- data.frame(conc = conc, time = time)
  if (!any(time == start)) {
    in_int <- time >= start & time <= end
    c0 <- PKNCA::pk.calc.c0(conc[in_int], time[in_int], time.dose = start, method = "logslope")
    if (!is.na(c0)) {
      d <- rbind(d, data.frame(conc = c0, time = start))
      d <- d[order(d$time), ]
    }
  }
  d
}

#' Imputation method for the concentration at dose time.
choose_impute <- function(cfg, dose_duration_h) {
  m <- cfg$nca$c0_imputation
  if (m == "auto") m <- if (all(dose_duration_h == 0)) "start_logslope" else "start_conc0"
  if (m == "none") NA_character_ else m
}

nca_options <- function(cfg) {
  list(
    auc.method = cfg$nca$auc_method,
    min.hl.points = cfg$nca$min_hl_points,
    allow.tmax.in.half.life = cfg$nca$allow_tmax_in_half_life,
    adj.r.squared.factor = cfg$nca$adj_r_squared_factor,
    progress = FALSE
  )
}

nca_units <- function(cfg) {
  u <- cfg$units
  PKNCA::pknca_units_table(
    concu = u$conc, doseu = u$dose, amountu = u$dose, timeu = u$time,
    conversions = data.frame(
      PPORRESU = c(sprintf("%s/(%s*%s)", u$dose, u$time, u$conc), sprintf("%s/(%s)", u$dose, u$conc),
                   sprintf("%s/%s", u$dose, u$dose)),
      PPSTRESU = c("L/h", "L", "%")
    )
  )
}

#' NCA for blood and plasma (0-inf, single IV dose).
#'
#' @param conc data.frame with USUBJID, PCSPEC, AFRLT, NFRLT, AVAL (NA rows are dropped by PKNCA).
#' @param dose data.frame with USUBJID, DOSEA, ADOSEDUR (one row per subject, dose at time 0).
#' @return data.frame of PKNCA results (long format, one row per subject/matrix/parameter).
run_systemic_nca <- function(conc, dose, cfg) {
  dose$TIME <- 0
  o_conc <- PKNCA::PKNCAconc(conc, AVAL ~ AFRLT | PCSPEC + USUBJID, time.nominal = "NFRLT")
  o_dose <- PKNCA::PKNCAdose(dose, DOSEA ~ TIME | USUBJID, route = "intravascular", duration = "ADOSEDUR")
  # Two interval rows over [0, Inf): "auc" with C0 imputation (+ lambda.z for a consistency
  # check), "observed" without imputation for everything else.
  intervals <- data.frame(start = 0, end = Inf, NCA_SET = c("auc", "observed"),
                          impute = c(choose_impute(cfg, dose$ADOSEDUR), NA_character_))
  intervals[SYSTEMIC_PARAMS] <- FALSE
  intervals[1, c(AUC_PARAMS, "lambda.z")] <- TRUE
  intervals[2, setdiff(SYSTEMIC_PARAMS, AUC_PARAMS)] <- TRUE
  opts <- c(nca_options(cfg), list(keep_interval_cols = "NCA_SET"))
  d <- PKNCA::PKNCAdata(o_conc, o_dose, intervals = intervals, units = nca_units(cfg),
                        impute = "impute", options = opts)
  res <- data.frame(as.data.frame(PKNCA::pk.nca(d)))

  # The imputed C0 must not change the terminal phase: lambda.z has to be identical in both sets.
  lz <- res[res$PPTESTCD == "lambda.z", ]
  lz <- merge(lz[lz$NCA_SET == "auc", c("PCSPEC", "USUBJID", "PPORRES")],
              lz[lz$NCA_SET == "observed", c("PCSPEC", "USUBJID", "PPORRES")],
              by = c("PCSPEC", "USUBJID"))
  differs <- !mapply(function(a, b) isTRUE(all.equal(a, b)), lz$PPORRES.x, lz$PPORRES.y)
  if (any(differs)) {
    warning("lambda_z differs with/without C0 imputation for: ",
            paste(lz$PCSPEC[differs], lz$USUBJID[differs], collapse = ", "),
            " - AUC0-inf/CL/Vz use the imputed set; check output/lambda_z_diagnostics.csv")
  }
  # PKNCA also reports dependencies (e.g. tmax, half.life) in the "auc" set: keep only AUC_PARAMS there.
  res[ifelse(res$NCA_SET == "auc", res$PPTESTCD %in% AUC_PARAMS, !res$PPTESTCD %in% AUC_PARAMS), ]
}

#' Quality flags for the terminal phase per subject/matrix (values are kept, only flagged).
nca_flags <- function(wide, cfg) {
  f <- character(nrow(wide))
  add <- function(f, cond, txt) ifelse(!is.na(cond) & cond, ifelse(f == "", txt, paste(f, txt, sep = "; ")), f)
  f <- add(f, is.na(wide$lambda.z), "lambda_z not estimable")
  f <- add(f, wide$aucpext.obs > cfg$nca$max_aucinf_pext, sprintf("AUC %%extrap > %g%%", cfg$nca$max_aucinf_pext))
  f <- add(f, wide$adj.r.squared < cfg$nca$min_hl_r_squared, sprintf("adj. R2 < %g", cfg$nca$min_hl_r_squared))
  f <- add(f, wide$span.ratio < cfg$nca$min_span_ratio, sprintf("span ratio < %g", cfg$nca$min_span_ratio))
  f
}

#' Long PKNCA result -> one row per subject/matrix with one column per parameter (standardised units).
pivot_results <- function(res_df, id_cols) {
  res_df <- data.frame(res_df)
  res_df <- res_df[res_df$PPTESTCD %in% names(PARAM_LABELS), ]
  w <- stats::reshape(res_df[, c(id_cols, "PPTESTCD", "PPSTRES")], idvar = id_cols,
                      timevar = "PPTESTCD", direction = "wide")
  names(w) <- sub("^PPSTRES\\.", "", names(w))
  rownames(w) <- NULL
  w
}

#' Units of each parameter as reported (PPSTRESU), for column headers and summary tables.
param_units <- function(res_df) {
  u <- unique(res_df[, c("PPTESTCD", "PPSTRESU")])
  stats::setNames(u$PPSTRESU, u$PPTESTCD)
}

#' Urine excretion.
#'
#' Per collection interval Ae = C_urine x V_urine (computed directly: PKNCA selects samples with
#' start <= time <= end, which would also pick up the adjacent collection). Cumulative Ae and fe
#' up to the end of each collection come from PKNCA (ae, fe) with time = end of collection, where
#' interval [0, end_k] contains exactly the collections ending at or before end_k.
#'
#' Concentrations are first converted to dose units per volume unit (e.g. kBq/mL -> MBq/mL), so
#' that Ae is in the dose unit and fe = Ae / dose is dimensionless.
#'
#' @param urine data.frame with USUBJID, AFRLT (start), AEFRLT (end), NFRLT, NAEFRLT, AVAL, VOLUME.
#' @param dose data.frame with USUBJID, DOSEA.
#' @return data.frame, one row per collection interval (AE, AE_CUM in units$dose).
run_urine_nca <- function(urine, dose, cfg) {
  amount_conc_unit <- sprintf("%s/%s", cfg$units$dose, cfg$units$volume)
  urine <- urine[order(urine$USUBJID, urine$AEFRLT), ]
  urine$CONC_AMT <- urine$AVAL * unit_factor(cfg$units$conc, amount_conc_unit)
  urine$AE <- urine$CONC_AMT * urine$VOLUME
  urine <- merge(urine[setdiff(names(urine), "DOSEA")], dose[, c("USUBJID", "DOSEA")], by = "USUBJID")
  urine$FE_PCT <- 100 * urine$AE / urine$DOSEA

  dose$TIME <- 0
  cfg_amt <- cfg
  cfg_amt$units$conc <- amount_conc_unit
  o_conc <- PKNCA::PKNCAconc(urine, CONC_AMT ~ AEFRLT | USUBJID, volume = "VOLUME")
  o_dose <- PKNCA::PKNCAdose(dose, DOSEA ~ TIME | USUBJID, route = "intravascular")
  intervals <- data.frame(USUBJID = urine$USUBJID, start = 0, end = urine$AEFRLT, ae = TRUE, fe = TRUE)
  d <- PKNCA::PKNCAdata(o_conc, o_dose, intervals = intervals, units = nca_units(cfg_amt), options = nca_options(cfg))
  res <- data.frame(as.data.frame(PKNCA::pk.nca(d)))
  cum <- stats::reshape(res[, c("USUBJID", "end", "PPTESTCD", "PPSTRES")], idvar = c("USUBJID", "end"),
                        timevar = "PPTESTCD", direction = "wide")
  names(cum) <- c("USUBJID", "AEFRLT", "AE_CUM", "FE_CUM_PCT")
  out <- merge(urine, cum, by = c("USUBJID", "AEFRLT"))
  out <- out[order(out$USUBJID, out$AEFRLT), ]

  # Internal consistency check: PKNCA cumulative Ae must equal the running sum of interval Ae.
  check <- stats::ave(out$AE, out$USUBJID, FUN = function(x) cumsum(ifelse(is.na(x), 0, x)))
  if (!isTRUE(all.equal(check, out$AE_CUM, tolerance = 1e-8))) {
    stop("Cumulative Ae from PKNCA differs from the sum of interval Ae")
  }
  out
}

#' Plasma AUC(0-T) for one subject, consistent with the main NCA: same C0 imputation and AUC
#' method; if T is not a sampling time, C(T) is interpolated with the same method.
#' (PKNCA's aucint.* ignores the interval imputation and does its own dose-aware
#' interpolation, which gave a different AUC for an IV bolus - see tests.)
plasma_auc_0_t <- function(time, conc, end, cfg, duration_h) {
  ok <- !is.na(conc) & time >= 0
  time <- time[ok]
  conc <- conc[ok]
  if (end > max(time)) stop("End of urine collection (", end, " h) is after the last plasma sample")
  imp <- choose_impute(cfg, duration_h)
  if (!is.na(imp) && !any(time == 0)) {
    d <- if (imp == "start_logslope") {
      PKNCA_impute_method_start_logslope(conc, time, start = 0, end = Inf)
    } else {
      data.frame(conc = c(0, conc), time = c(0, time))
    }
    conc <- d$conc
    time <- d$time
  }
  if (!any(time == end)) {
    c_end <- PKNCA::interpolate.conc(conc, time, time.out = end, method = cfg$nca$auc_method)
    conc <- c(conc[time < end], c_end)
    time <- c(time[time < end], end)
  } else {
    conc <- conc[time <= end]
    time <- time[time <= end]
  }
  PKNCA::pk.calc.auc.last(conc, time, method = cfg$nca$auc_method)
}

#' Renal clearance CLr = Ae(0-T) / AUC_plasma(0-T), T = end of the last urine collection per subject.
run_renal_clearance <- function(plasma, urine_res, dose, cfg) {
  last <- urine_res[!duplicated(urine_res$USUBJID, fromLast = TRUE), c("USUBJID", "AEFRLT", "AE_CUM", "FE_CUM_PCT")]
  last$AUC_PLASMA_0_T <- vapply(seq_len(nrow(last)), function(i) {
    p <- plasma[plasma$USUBJID == last$USUBJID[i], ]
    plasma_auc_0_t(p$AFRLT, p$AVAL, last$AEFRLT[i], cfg, dose$ADOSEDUR[dose$USUBJID == last$USUBJID[i]])
  }, numeric(1))
  last$AUC_UNIT <- sprintf("%s*%s", cfg$units$time, cfg$units$conc)
  names(last)[names(last) == "AEFRLT"] <- "T_H"
  # e.g. MBq / (h * kBq/mL) -> L/h
  clr_unit <- sprintf("%s/(%s*%s)", cfg$units$dose, cfg$units$time, cfg$units$conc)
  last$CLR_L_PER_H <- last$AE_CUM / last$AUC_PLASMA_0_T * unit_factor(clr_unit, "L/h")
  last
}
