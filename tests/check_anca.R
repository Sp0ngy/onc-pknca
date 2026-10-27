# Headless check of data/adnca.csv against aNCA's own data pipeline (no Shiny needed).
# Replays what the app does on upload -> mapping -> NCA -> excretion, and compares the results
# with R/run_nca.R. Run from the project root after R/preprocess.R and R/run_nca.R:
#   source("tests/check_anca.R")

suppressPackageStartupMessages(library(aNCA))   # attached: PKNCA finds aNCA's impute methods by name
library(dplyr, warn.conflicts = FALSE)
source("R/functions.R")
source("R/nca.R")
cfg <- load_config("config/config.yml")

# 1) Upload: aNCA::read_pk() is what the "Upload" tab calls.
raw <- read_pk("data/adnca.csv")

# 2) Mapping: our column names equal aNCA's target names, so the app pre-selects each one.
vars <- c("STUDYID", "USUBJID", "PARAM", "PCSPEC", "ATPTREF", "AVAL", "AVALU", "AFRLT", "ARRLT",
          "NRRLT", "NFRLT", "RRLTU", "ROUTE", "DOSETRT", "DOSEA", "DOSEU", "ADOSEDUR", "VOLUME",
          "VOLUMEU", "TRTRINT", "METABFL")
mapping <- as.list(ifelse(vars %in% names(raw), vars, ""))
names(mapping) <- vars
mapping$Grouping_Variables <- character(0)
mapping$Metabolites <- character(0)
mapped <- withCallingHandlers(
  apply_mapping(raw, mapping, vars, silent = TRUE),
  warning = function(w) {
    message("aNCA mapping warning: ", conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)
mapped <- create_metabfl(mapped, character(0))
mapped$DFLAG <- FALSE
stopifnot(nrow(mapped) == nrow(raw))
message("Mapping OK: ", nrow(mapped), " rows, ", ncol(mapped), " columns")

# 3) PKNCA data object as built by the app (units table must accept MBq and MBq/mL).
pk <- PKNCA_create_data_object(mapped)
print(PKNCA_build_units_table(pk$conc, pk$dose) |>
        filter(PPTESTCD %in% c("cmax", "aucinf.obs", "cl.obs", "vz.obs", "ae", "fe")) |>
        distinct(PPTESTCD, PPORRESU))
print(detect_study_types(pk$conc$data, groups = c("USUBJID", "PCSPEC"), metabfl_column = "METABFL",
                         route_column = "std_route", volume_column = "VOLUME") |> distinct(PCSPEC, type))

# 4) Main NCA as run by the app for blood + plasma (default parameter set of the setup tab).
params <- c("cmax", "tmax", "auclast", "aucinf.obs", "half.life", "lambda.z", "cl.obs", "vz.obs",
            "aucpext.obs", "adj.r.squared", "lambda.z.n.points")
nca_in <- PKNCA_update_data_object(
  pk, auc_data = data.frame(start_auc = numeric(0), end_auc = numeric(0)), method = cfg$nca$auc_method,
  selected_analytes = cfg$study$param, selected_profile = "DOSE 1",
  selected_pcspec = c("BLOOD", "PLASMA"), params = params, should_impute_c0 = TRUE
)
anca_res <- PKNCA_calculate_nca(nca_in)$result |>
  filter(type_interval == "main", PPTESTCD %in% params) |>
  select(PCSPEC, USUBJID, PPTESTCD, ANCA = PPORRES)

ours <- run_systemic_nca(mapped[mapped$PCSPEC %in% c("BLOOD", "PLASMA") & !is.na(mapped$AVAL), ],
                         unique(mapped[, c("USUBJID", "DOSEA", "ADOSEDUR")]), cfg) |>
  select(PCSPEC, USUBJID, PPTESTCD, SCRIPT = PPORRES)
cmp <- inner_join(anca_res, ours, by = c("PCSPEC", "USUBJID", "PPTESTCD")) |>
  mutate(REL_DIFF = ifelse(SCRIPT == 0, ANCA - SCRIPT, (ANCA - SCRIPT) / SCRIPT))
cat("\naNCA vs R/run_nca.R (blood + plasma), max |relative difference| per parameter:\n")
print(cmp |> group_by(PPTESTCD) |> summarise(n = n(), max_abs_rel_diff = max(abs(REL_DIFF))), n = 50)

# 5) Excretion module: replicates shiny/modules/tab_nca/excretion_analysis.R (sample intervals
#    start = AFRLT, end = AEFRLT; profile interval 0-Inf), then compares Ae with AVAL x VOLUME.
ex <- pk
all_params <- setdiff(names(PKNCA::get.interval.cols()), c("start", "end"))
conc_groups <- unname(unlist(ex$conc$columns$groups))
sample_int <- ex$conc$data |>
  select(any_of(c(conc_groups, "AEFRLT", "AFRLT"))) |>
  mutate(PCSPEC = as.character(PCSPEC)) |>
  rename(start = AFRLT, end = AEFRLT) |>
  filter(PCSPEC == "URINE") |>
  distinct()
sample_int[all_params] <- FALSE
sample_int$ae <- TRUE
sample_int$fe <- TRUE
sample_int$type_interval <- "sample"
profile_int <- format_pkncadata_intervals(ex$conc, ex$dose, params = c("ae", "fe")) |>
  mutate(type_interval = "profile") |>
  filter(PCSPEC == "URINE")
ex$intervals <- bind_rows(profile_int, sample_int)
ex$options$keep_interval_cols <- c("ATPTREF", "type_interval")
ex_res <- suppressWarnings(PKNCA::pk.nca(ex, verbose = FALSE))$result

urine <- mapped[mapped$PCSPEC == "URINE", ]
expected <- urine |> transmute(USUBJID, start = AFRLT, end = AEFRLT, AE_EXPECTED = AVAL * VOLUME)
ae_sample <- ex_res |> filter(type_interval == "sample", PPTESTCD == "ae") |>
  select(USUBJID, start, end, AE_ANCA = PPORRES) |>
  inner_join(expected, by = c("USUBJID", "start", "end")) |>
  mutate(RATIO = AE_ANCA / AE_EXPECTED)
cat("\naNCA excretion module, Ae per collection interval vs. C x V (first subject):\n")
print(ae_sample |> filter(USUBJID == first(USUBJID)))
n_wrong <- sum(abs(ae_sample$RATIO - 1) > 1e-8, na.rm = TRUE)
cat(sprintf("Intervals where aNCA Ae != C x V: %d of %d\n", n_wrong, nrow(ae_sample)))

ae_profile <- ex_res |> filter(type_interval == "profile", PPTESTCD %in% c("ae", "fe")) |>
  select(USUBJID, PPTESTCD, PPORRES)
tot <- expected |> group_by(USUBJID) |> summarise(AE_TOTAL = sum(AE_EXPECTED))
cat("\naNCA excretion module, profile interval (0-Inf) Ae vs. sum of C x V:\n")
print(ae_profile |> filter(PPTESTCD == "ae") |> inner_join(tot, by = "USUBJID") |>
        mutate(RATIO = PPORRES / AE_TOTAL))
