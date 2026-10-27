# onc-pknca: PKNCA + aNCA test setup for radiopharmaceutical PK

First fit-for-purpose test of **PKNCA** (R NCA engine) and **aNCA** (pharmaverse Shiny GUI on
PKNCA) as a possible replacement for the current Excel workbook + NUKFIT analysis of gamma counter
data (total radioactivity in whole blood, plasma and urine after a single IV administration).

**Status: test setup, not a validated system.** It is built so that it can grow into one:
version-locked packages (`renv.lock`), scripted and parameterised (`config/config.yml`),
traceable outputs (`output/run_info_*.txt` with git commit, package versions, input checksums),
unit tests, and git history. Only synthetic data is in the repository.

| Component | Version |
|---|---|
| R | 4.6.1 |
| PKNCA | 0.12.1 (same version as the Atorus OpenVal release) |
| aNCA | 0.1.0 (CRAN) |
| renv | 1.3.1 |

## Quick start (Windows)

1. **Install R ≥ 4.4** from <https://cloud.r-project.org/bin/windows/base/> (this repo was built with 4.6.1), or with winget:
   ```bash
   winget install --id RProject.R --version 4.6.1
   ```
   RStudio (optional): <https://posit.co/download/rstudio-desktop/>. Rtools is **not** needed, all packages install as binaries.
2. **Clone** the repository:
   ```bash
   git clone https://github.com/Sp0ngy/onc-pknca.git
   ```
3. **Open** `onc-pknca.Rproj` in RStudio (or start R with the repository folder as working directory).
   renv activates itself through `.Rprofile`.
4. **Restore the locked packages** (once, takes a few minutes):
   ```r
   renv::restore()
   ```
5. **Preprocess** the input data → `data/adnca.csv` + concentration and B:P tables in `output/`.
   Input is either decay-corrected concentrations (e.g. kBq/mL) vs. time after injection in h
   (`input: format: "concentrations"`, default) or raw gamma counter data (`"gamma_counts"`),
   see [templates/README.md](templates/README.md):
   ```r
   source("R/preprocess.R")
   ```
6. Either **GUI**: start aNCA and upload `data/adnca.csv` (see [Using aNCA](#using-anca-with-this-data)):
   ```r
   aNCA::run_app()
   ```
   or **script**: the same NCA plus urine parameters in code, results in `output/`:
   ```r
   source("R/run_nca.R")
   ```
7. **Tests**:
   ```r
   source("tests/run_tests.R")     # unit tests incl. hand-calculated NCA reference subject
   source("tests/check_anca.R")    # replays aNCA's own data pipeline headlessly on data/adnca.csv
   ```

If R says it cannot write to the library during step 4, create the user library first:
`dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE)`.

## Repository layout

```
config/config.yml           nuclide half-life, decay correction on/off, BLQ rule, LLOQ, units, NCA settings
templates/                  CSV templates for both input formats (concentrations, gamma counts) + dosing
data-raw/make_dummy_data.R  generator of the synthetic study as raw gamma counts (seeded, reproducible)
data-raw/make_dummy_concentrations.R  converts it to decay-corrected kBq/mL vs. h
data-raw/dummy_*.csv        synthetic Lu-177 study: 8 subjects, blood + plasma + urine, both formats
data-raw/study/             place for real study data - git-ignored, never commit it
R/functions.R               decay correction, counts -> MBq/mL, dose, BLQ, B:P ratio, statistics
R/nca.R                     PKNCA wrappers: blood/plasma NCA, urine Ae/fe, CLr
R/io.R                      output writer (adds decay-correction mode) + run_info
R/preprocess.R              script: raw data -> data/adnca.csv + tables
R/run_nca.R                 script: NCA -> output/
tests/testthat/             unit tests
tests/check_anca.R          headless aNCA compatibility check
data/, output/              generated, git-ignored
```

## Calculation conventions

* **Input format `concentrations`:** CONC is converted from `input: conc_unit` to `units: conc`
  (default kBq/mL for both). If it is already decay-corrected to injection time
  (`input: decay_corrected_to_injection: true`), the as-sampled value used for BLQ and for the
  effective mode is C × e^(−λp·t) with t = sampling time (urine: end of collection).
  `BLQ`/`<LLOQ`-type entries are treated as BLQ.
* **Units:** concentrations and AUC are reported in `units: conc` (kBq/mL, h·kBq/mL),
  dose and Ae in MBq, CL and CLr in L/h, Vz in L, fe in %.
* **Counts → activity concentration (format `gamma_counts`):**
  `MBq/mL = (GROSS_COUNTS / COUNT_TIME_MIN − BACKGROUND_CPM) / CAL_CPM_PER_BQ × DILUTION_FACTOR / aliquot mL / 10⁶`.
  Aliquot weight is converted with the matrix density if no volume is given.
* **Decay correction (two steps):**
  1. always from counting time back to the time the sample left the body (blood/plasma: sampling
     time, urine: end of collection). Decay in the tube is an artefact of when the lab counted.
  2. optionally (`decay_correction: to_injection`) on to injection time →
     λz/t½ are **biological**; switched off → **effective** half-life.
     For urine this is exact: activity keeps decaying at the same rate in the bladder and
     collection container, so the end-of-collection activity × e^(λ·t_end) is the excreted
     activity at injection-time reference regardless of when within the interval it was excreted.

  Every output table starts with a `DECAY_CORRECTION` column stating the mode; the ADNCA file has `DECAYCFL`.
* **Dose** = net injected activity at injection time = syringe before injection − residual,
  both decay-corrected to injection time.
* **BLQ:** judged on the as-sampled activity concentration (before correction to injection,
  because the LLOQ is a property of the measurement). Rules configurable; default for
  blood/plasma: 0 before the first quantifiable value, missing afterwards; urine: 0.
* **NCA (PKNCA):** linear-up/log-down AUC; λz by log-linear regression on ≥ 3 points after Cmax,
  chosen by adjusted R² (PKNCA default rule); AUC0-inf = AUClast + Clast,obs/λz; CL = Dose/AUC0-inf;
  Vz = CL/λz. For an IV bolus, C0 is back-extrapolated log-linearly from the first two samples
  and used **only** for AUC-based parameters (AUC, %extrap, CL, Vz); Cmax/Tmax are observed values.
  Quality flags (%AUCextrap > 20 %, adj. R² < 0.9, span ratio < 2) are reported, not used to delete values.
* **Urine:** Ae per interval = C_urine × V_urine; cumulative Ae and fe (% of injected activity) via
  PKNCA (`ae`, `fe`) and cross-checked against the running sum; CLr = Ae(0–T) / plasma AUC(0–T),
  T = end of last collection, plasma AUC with the same C0 imputation and interpolation as the main NCA.
* **Blood-to-plasma ratio:** blood/plasma per subject and nominal time (same draw), only where
  both are quantifiable; summary per nominal time.
* Date-times are interpreted as UTC so that daylight-saving changes cannot distort time differences.

## Outputs

| File | Content |
|---|---|
| `data/adnca.csv` | ADNCA input for aNCA and `R/run_nca.R` |
| `output/dose.csv` | net injected activity per subject |
| `output/concentrations.csv` | full derivation per sample: counts, net cpm, MBq/mL at counting/sampling/reported, BLQ |
| `output/concentration_summary.csv` | descriptive stats per matrix and nominal time |
| `output/bp_ratio_individual.csv`, `bp_ratio_summary.csv` | whole blood-to-plasma ratio |
| `output/nca_parameters.csv` | Cmax, Tmax, AUC0-t, AUC0-inf, %extrap, λz, t½, CL, Vz + λz diagnostics + flags, per subject and matrix |
| `output/nca_parameters_long.csv` | all PKNCA results, original and standardised units |
| `output/nca_summary.csv` | n, mean, SD, CV%, geo. mean, geo. CV%, median, min, max |
| `output/lambda_z_diagnostics.csv`, `lambda_z_plots.pdf` | terminal-phase regression details and plots |
| `output/urine_intervals.csv`, `urine_summary.csv` | Ae, fe per interval and cumulative, excretion rate per interval |
| `output/urine_rmax.csv`, `urine_rmax_summary.csv` | Rmax (max. urinary excretion rate) and TRmax (midpoint of that interval) |
| `output/renal_clearance.csv`, `renal_clearance_summary.csv` | Ae(0–T), fe(0–T), plasma AUC(0–T), CLr |
| `output/run_info_*.txt` | time, git commit, R/package versions, input MD5, full configuration |

## Using aNCA with this data

1. `aNCA::run_app()` → **Data** tab → upload `data/adnca.csv`.
2. **Mapping:** all columns carry aNCA's target names (STUDYID, USUBJID, PARAM, PCSPEC, ATPTREF,
   AVAL, AVALU, AFRLT, ARRLT, NFRLT, NRRLT, RRLTU, ROUTE, DOSETRT, DOSEA, DOSEU, ADOSEDUR,
   VOLUME, VOLUMEU), so they are pre-selected. Confirm.
3. **NCA setup:** select matrices **BLOOD** and **PLASMA** only (urine rows are concentrations of
   collected urine, not a plasma-like profile). AUC method "lin up/log down".
   aNCA detects the profiles as "Single IV Bolus" and back-extrapolates C0 for AUC (same as the script).
   Leave **Impute Concentration** on. Flag rule R2ADJ defaults to 0.7; set 0.9 to match the script.
4. **Units:** with kBq/mL and MBq, aNCA labels CL `MBq/(h*kBq/mL)` and Vz `MBq/(kBq/mL)`, which
   are numerically L/h and L; set them in the units dialog to get the labels.
   fe is shown as kBq/MBq (×0.1 = %), Ae in kBq.
5. **Urine (Excretion tab):** select URINE, end time column **AEFRLT**, and **untick
   "Adjust for Body Weight"** (ticked by default; it multiplies the dose by body weight).
   See the known issue below before using per-interval Ae from aNCA.
6. **Mapping → Grouping_Variables:** aNCA pre-fills AGE and SEX; remove AGE (it makes every subject
   its own group in the summaries).
7. **Exploration → Mean Plots:** the default grouping DOSEA gives "Data issue" because every subject
   has an individual injected activity. Switch to PCSPEC by *first adding* PCSPEC and *then* removing
   DOSEA — an empty grouping field crashes the app (see findings).

## Findings of this test

### 1. Blood/plasma: aNCA = scripted PKNCA

`tests/check_anca.R` replays aNCA's upload → mapping → `PKNCA_create_data_object()` →
`PKNCA_update_data_object()` → `PKNCA_calculate_nca()` on `data/adnca.csv`. For all 16
profiles (8 subjects × blood/plasma) Cmax, Tmax, AUC0-t, AUC0-inf, %extrap, λz, t½, adj. R², n points,
CL and Vz are **identical** to `R/run_nca.R` (relative difference 0), with kBq/mL as well as
MBq/mL concentrations. The data mapping accepts both without changes.

### 2. Urine: aNCA has an excretion module, but per-interval Ae is wrong in aNCA 0.1.0

aNCA 0.1.0 handles urine through a separate "Excretion" analysis (needs `VOLUME`, `VOLUMEU`
and an end-time column such as `AEFRLT`) and offers Ae, fe, CLr, volume parameters.

* **Per collection interval:** aNCA builds intervals `[AFRLT, AEFRLT]`, but PKNCA selects samples
  with `start ≤ time ≤ end`, so the sample of the *next* collection (whose start time equals this
  end time) is added. In the dummy data 40 of 48 interval Ae values are 1.5–3.1× too high (only
  each subject's last interval is right). Cumulative Ae/fe over 0–∞ is correct.
* "Adjust for Body Weight" is ticked by default and changes the dose to MBq × kg.
* CLr needs urine Ae and plasma AUC from two different matrices. aNCA runs PKNCA grouped by
  matrix, so its CLr options would not use the plasma AUC (not tested further).
* fe is reported relative to `DOSEA`, which is correct here because DOSEA is the net injected activity.

→ **Urine is covered in `R/run_nca.R`** (Ae per interval as C × V, cumulative Ae/fe via PKNCA with
a consistency check, CLr against plasma AUC over the same time). Worth reporting upstream to
pharmaverse/aNCA.

### 3. Things in PKNCA to be aware of

* PKNCA 0.12.1 has no built-in "back-extrapolate C0" imputation; aNCA adds one, and
  `R/nca.R` registers an equivalent function (based on `PKNCA::pk.calc.c0(method = "logslope")`).
* With imputation, PKNCA reports the imputed C0 as Cmax at Tmax = 0. `R/nca.R` therefore
  calculates Cmax/Tmax/λz without imputation and AUC/CL/Vz with it, and checks that λz is the
  same in both.
* `aucint.*` ignores the interval imputation (gave 98.5 instead of 102 h·MBq/mL in the reference
  test), so the plasma AUC(0–T) for CLr is calculated from PKNCA's lower-level functions instead.

### 4. Differences to expect vs. Excel/NUKFIT

* **λz / t½:** NCA estimates λz from a log-linear regression over the last ≥ 3 points, selected
  automatically by adjusted R². NUKFIT fits a sum of exponentials to all points; the terminal
  t½ is the slowest fitted component. If the terminal phase is not reached or sampling is
  sparse, NCA λz can include part of the intermediate phase (shorter t½); the fit may separate
  phases better but depends on the model (number of exponentials, weighting). In the dummy data
  the regression start varies between 24 and 72 h across subjects — check
  `lambda_z_plots.pdf` and fix the points manually in aNCA where needed.
* **AUC0-inf:** NCA = trapezoids (lin-up/log-down) + Clast/λz; NUKFIT = Σ Aᵢ/λᵢ analytically.
  AUC0-t agrees closely with dense sampling; differences come from the first segment
  (C0 back-extrapolation from two points vs. fitted intercepts, relevant for fast
  distribution phases) and from the extrapolated part if %AUCextrap is large.
* **CL, Vz:** follow from the above; Vz = CL/λz is sensitive to λz. NUKFIT may report Vss or a
  model volume instead, which is not the same parameter.
* **BLQ:** make sure both use the same rule (here configurable).
* **Decay correction:** confirm which mode the Excel workbook uses for each parameter
  (biological vs. effective t½; fe normally decay-corrected).
* Planned PQ: run the same reference datasets through both and define acceptance criteria
  (e.g. AUC ±5 %, t½ ±10 %).

### 5. aNCA data mapping vs. radioactivity data

* MBq, kBq/mL, MBq/mL, h and mL are all understood by the `units` package aNCA uses; no conflicts.
* Derived units stay unsimplified (`MBq/(h*kBq/mL)`) unless converted in the units dialog.
* `PARAM` = "Total radioactivity" is a single analyte; aNCA's metabolite flag stays empty
  (gamma counting does not separate parent, metabolites and free nuclide).
* Required columns AVALU, RRLTU and DOSEU are mandatory in the mapping (not only the columns
  listed in the aNCA manual).
* `ROUTE = "INTRAVENOUS"` is classified as intravascular; `ADOSEDUR = 0` → IV bolus,
  > 0 → IV infusion (C0 = 0 instead of back-extrapolation).

### 6. aNCA app issues found during the GUI walkthrough (0.1.0)

* **Crash with an empty mean-plot grouping:** removing the last variable from
  Exploration → Mean Plots → "group by" calls `interaction()` without factors and stops the R
  session ("Keine Faktoren angegeben" / "No factors specified"); the app has to be restarted and the
  data re-uploaded.
* **Broken option in the same list:** an entry `function () { if (.destroyed) …` (a Shiny reactive
  printed instead of its value) appears among the grouping variables.
* **Default mean-plot grouping DOSEA** does not fit individually measured activities (every group
  has n = 1 → "Data issue: No data with more than 3 points").
* **Ratio calculations:** test/reference groups are easy to swap; check that the AUC ratio is
  blood/plasma (≈ 0.66 here), not plasma/blood (≈ 1.5).
* Session state lives only in memory: after a crash or restart all settings, point exclusions
  and results are lost unless exported.

## Out of scope (for now)

Formal 21 CFR Part 11 validation (risk-based approach per R Validation Hub, riskmetric/riskassessment,
PKNCA's installed test suite as IQ/OQ, own PQ against Excel/NUKFIT reference results, possibly
Atorus OpenVal), popPK/PBPK.
