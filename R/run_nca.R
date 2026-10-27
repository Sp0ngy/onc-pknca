# Scripted NCA with PKNCA: blood + plasma (0-inf) and urine (Ae, fe, CLr).
#
# Run from the project root:  source("R/run_nca.R")   (runs R/preprocess.R first if needed)
# Outputs : output/nca_parameters_long.csv     all PKNCA results (original + standardised units)
#           output/nca_parameters.csv          one row per subject and matrix
#           output/nca_summary.csv             descriptive statistics per matrix and parameter
#           output/lambda_z_diagnostics.csv    terminal-phase regression details + quality flags
#           output/lambda_z_plots.pdf          log-linear plots with the selected regression points
#           output/urine_intervals.csv         Ae and fe per collection interval, cumulative Ae / fe
#           output/urine_summary.csv           descriptive statistics per interval
#           output/urine_rmax.csv              Rmax (max. excretion rate) and TRmax per subject (+ summary)
#           output/renal_clearance.csv         CLr per subject (+ summary rows)
#           output/run_info_nca.txt            versions, checksums, configuration

source("R/functions.R")
source("R/io.R")
source("R/nca.R")

cfg <- load_config("config/config.yml")
if (!file.exists("data/adnca.csv")) source("R/preprocess.R")
adnca <- utils::read.csv("data/adnca.csv", stringsAsFactors = FALSE)
if (any(adnca$DECAYCFL != (if (cfg$decay_correction$to_injection) "Y" else "N"))) {
  stop("data/adnca.csv was created with a different decay-correction setting - rerun R/preprocess.R")
}
message("NCA - ", decay_label(cfg$decay_correction$to_injection), "; AUC method: ", cfg$nca$auc_method)

dose <- unique(adnca[, c("USUBJID", "DOSEA", "ADOSEDUR")])
systemic <- adnca[adnca$PCSPEC %in% c("BLOOD", "PLASMA") & !is.na(adnca$AVAL), ]
urine <- adnca[adnca$PCSPEC == "URINE", ]

# ---- blood and plasma --------------------------------------------------------------------------

res_df <- run_systemic_nca(systemic, dose, cfg)
res_df$PARAMETER <- unname(PARAM_LABELS[res_df$PPTESTCD])
write_output(res_df, "output/nca_parameters_long.csv", cfg)

id_cols <- c("PCSPEC", "USUBJID")
wide <- pivot_results(res_df, id_cols)
wide$FLAGS <- nca_flags(wide, cfg)
units <- param_units(res_df)
report <- wide[, c(id_cols, intersect(SYSTEMIC_PARAMS, names(wide)), "FLAGS")]
names(report) <- ifelse(names(report) %in% names(units),
                        sprintf("%s [%s]", PARAM_LABELS[names(report)], units[names(report)]), names(report))
write_output(report[order(report$PCSPEC, report$USUBJID), ], "output/nca_parameters.csv", cfg)

summary_params <- c("cmax", "tmax", "auclast", "aucinf.obs", "aucpext.obs", "lambda.z", "half.life", "cl.obs", "vz.obs")
long_sum <- res_df[res_df$PPTESTCD %in% summary_params, ]
nca_sum <- summarise_by(long_sum, c("PCSPEC", "PPTESTCD"), "PPSTRES")
nca_sum <- cbind(nca_sum[, 1:2], PARAMETER = unname(PARAM_LABELS[nca_sum$PPTESTCD]),
                 UNIT = unname(units[nca_sum$PPTESTCD]), nca_sum[, -(1:2)])
nca_sum <- nca_sum[order(nca_sum$PCSPEC, match(nca_sum$PPTESTCD, summary_params)), ]
write_output(nca_sum, "output/nca_summary.csv", cfg)

diag_cols <- c("lambda.z", "half.life", "r.squared", "adj.r.squared", "lambda.z.n.points",
               "lambda.z.time.first", "tlast", "span.ratio", "aucpext.obs")
write_output(wide[order(wide$PCSPEC, wide$USUBJID), c(id_cols, diag_cols, "FLAGS")],
             "output/lambda_z_diagnostics.csv", cfg)

# Lambda-z plots: all points, points used in the regression highlighted, fitted line.
local({
  pts <- merge(systemic[systemic$AFRLT >= 0 & systemic$AVAL > 0, c(id_cols, "AFRLT", "AVAL")],
               wide[, c(id_cols, "lambda.z", "lambda.z.time.first", "tlast", "clast.obs", "half.life", "adj.r.squared")],
               by = id_cols)
  pts$USED <- !is.na(pts$lambda.z) & pts$AFRLT >= pts$lambda.z.time.first & pts$AFRLT <= pts$tlast
  fit <- do.call(rbind, lapply(split(pts[pts$USED, ], pts[pts$USED, id_cols], drop = TRUE), function(g) {
    m <- stats::lm(log(AVAL) ~ AFRLT, data = g)
    tt <- range(g$AFRLT)
    data.frame(g[1, id_cols], AFRLT = tt, AVAL = exp(unname(stats::predict(m, data.frame(AFRLT = tt)))), row.names = NULL)
  }))
  lab <- unique(pts[, c(id_cols, "half.life", "adj.r.squared")])
  lab$TXT <- sprintf("t1/2 = %.1f h, adj.R2 = %.3f", lab$half.life, lab$adj.r.squared)
  p <- ggplot2::ggplot(pts, ggplot2::aes(AFRLT, AVAL)) +
    ggplot2::geom_line(colour = "grey60") +
    ggplot2::geom_point(ggplot2::aes(colour = USED)) +
    ggplot2::geom_line(data = fit, colour = "firebrick", linetype = "dashed") +
    ggplot2::geom_text(data = lab, ggplot2::aes(x = Inf, y = Inf, label = TXT), hjust = 1.05, vjust = 1.5, size = 2.5,
                       inherit.aes = FALSE) +
    ggplot2::scale_y_log10() +
    ggplot2::scale_colour_manual(values = c(`TRUE` = "firebrick", `FALSE` = "grey30"), name = "In lambda_z") +
    ggplot2::facet_wrap(~ PCSPEC + USUBJID, ncol = 4) +
    ggplot2::labs(x = "Time after injection (h)", y = sprintf("Total radioactivity (%s)", cfg$units$conc),
                  title = "Terminal phase regression (lambda_z)",
                  subtitle = decay_label(cfg$decay_correction$to_injection)) +
    ggplot2::theme_bw(base_size = 8)
  ggplot2::ggsave("output/lambda_z_plots.pdf", p, width = 11, height = 8.5)
  message("  wrote output/lambda_z_plots.pdf")
})

# ---- urine -------------------------------------------------------------------------------------

if (nrow(urine)) {
  urine_res <- run_urine_nca(urine, dose, cfg)
  write_output(urine_res[, c("USUBJID", "SAMPLEID", "NFRLT", "NAEFRLT", "AFRLT", "AEFRLT", "AVAL", "VOLUME",
                             "AE", "FE_PCT", "AE_CUM", "FE_CUM_PCT", "RATE", "MIDPOINT", "DOSEA")],
               "output/urine_intervals.csv", cfg)

  rmax <- urine_rmax(urine_res)
  names(rmax)[names(rmax) == "RMAX"] <- sprintf("RMAX [%s/%s]", cfg$units$dose, cfg$units$time)
  names(rmax)[names(rmax) == "TRMAX"] <- sprintf("TRMAX [%s]", cfg$units$time)
  names(rmax)[names(rmax) %in% c("NFRLT", "NAEFRLT")] <- c("RMAX_INTERVAL_START_NOMINAL", "RMAX_INTERVAL_END_NOMINAL")
  write_output(rmax, "output/urine_rmax.csv", cfg)
  write_output(do.call(rbind, lapply(names(rmax)[2:3], function(v) cbind(PARAMETER = v, describe(rmax[[v]])))),
               "output/urine_rmax_summary.csv", cfg)
  urine_res$INTERVAL <- sprintf("%g-%g h", urine_res$NFRLT, urine_res$NAEFRLT)
  urine_long <- rbind(
    data.frame(urine_res[, c("NFRLT", "INTERVAL")], PARAMETER = sprintf("Ae [%s]", cfg$units$dose), VALUE = urine_res$AE),
    data.frame(urine_res[, c("NFRLT", "INTERVAL")], PARAMETER = "fe [%]", VALUE = urine_res$FE_PCT),
    data.frame(urine_res[, c("NFRLT", "INTERVAL")], PARAMETER = sprintf("Ae cumulative [%s]", cfg$units$dose), VALUE = urine_res$AE_CUM),
    data.frame(urine_res[, c("NFRLT", "INTERVAL")], PARAMETER = "fe cumulative [%]", VALUE = urine_res$FE_CUM_PCT)
  )
  write_output(summarise_by(urine_long, c("PARAMETER", "NFRLT", "INTERVAL"), "VALUE")[, -2],
               "output/urine_summary.csv", cfg)

  plasma <- systemic[systemic$PCSPEC == "PLASMA", ]
  clr <- run_renal_clearance(plasma, urine_res, dose, cfg)
  clr_sum <- do.call(rbind, lapply(c("AE_CUM", "FE_CUM_PCT", "AUC_PLASMA_0_T", "CLR_L_PER_H"), function(v) {
    cbind(PARAMETER = v, describe(clr[[v]]))
  }))
  write_output(clr, "output/renal_clearance.csv", cfg)
  write_output(clr_sum, "output/renal_clearance_summary.csv", cfg)
}

write_run_info("output/run_info_nca.txt", cfg, c("data/adnca.csv", "config/config.yml"), step = "R/run_nca.R")
message("NCA done.")
