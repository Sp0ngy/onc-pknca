# Input templates

Two input formats, selected with `input: format:` in `config/config.yml`. Each uses two CSV files
per study (UTF-8, comma-separated, one header row). Leave cells empty for "not applicable".

| Format | Files | Use when |
|---|---|---|
| `concentrations` (default) | `concentrations_template.csv` + `dosing_concentrations_template.csv` | the lab delivers activity concentrations (e.g. decay-corrected kBq/mL) vs. time after injection in h |
| `gamma_counts` | `gamma_counter_samples_template.csv` + `dosing_template.csv` | raw gamma counter output (counts, background, calibration, date-times) |

# Format `concentrations`

## `concentrations_template.csv` — one row per sample

| Column | Unit | Description |
|---|---|---|
| STUDYID | | Study identifier |
| USUBJID | | Unique subject identifier (must match the dosing file) |
| MATRIX | | `BLOOD`, `PLASMA` or `URINE` |
| SAMPLE_ID | | Lab sample ID (traceability only) |
| NOMINAL_START_H | h | Urine only: nominal start of the collection interval |
| NOMINAL_TIME_H | h | Blood/plasma: nominal sampling time. Urine: nominal end of collection. Pre-dose = 0 |
| START_TIME_H | h | Urine only: actual start of collection, hours after start of injection |
| TIME_H | h | Blood/plasma: actual sampling time; urine: actual end of collection; hours after start of injection (pre-dose negative) |
| CONC | `input: conc_unit` (e.g. kBq/mL) | Activity concentration. A number, or `BLQ` / `<LLOQ` / `BQL` / `<LOQ` / `<LOD` / `ND` for below the limit of quantification, or empty if not available |
| URINE_VOLUME_ML | mL | Urine only: total voided volume of the interval |
| COMMENT | | Free text |

Set in `config/config.yml`:
* `input: conc_unit` — unit of CONC (`kBq/mL`, `MBq/mL`, `Bq/mL`, …); converted to `units: conc`.
* `input: decay_corrected_to_injection` — `true` if CONC is already decay-corrected to injection
  time (urine: from the end of collection). With `decay_correction: to_injection: false` the
  pipeline then removes the correction (C_as_sampled = CONC × e^(−λp·TIME_H)) to report effective
  half-lives. BLQ against the LLOQ is always judged on the as-sampled value.
* `blq: lloq` — in `units: conc`. Use 0 if the lab already reports BLQ as text.

## `dosing_concentrations_template.csv` — one row per subject

| Column | Unit | Description |
|---|---|---|
| STUDYID, USUBJID | | As above |
| SEX, AGE, WEIGHT_KG | | Demographics, optional (carried into the ADNCA file) |
| NUCLIDE, DRUG | | Informational (the half-life used is the one in the config) |
| NET_INJECTED_MBQ | MBq | Net injected activity at injection time (syringe residual already subtracted) |
| INFUSION_DURATION_MIN | min | 0 for bolus |

# Format `gamma_counts`

Date-times as `YYYY-MM-DD HH:MM[:SS]`, all in the **same clock** (interpreted as UTC so that
daylight-saving changes cannot distort time differences).

## `gamma_counter_samples_template.csv` — one row per counted sample

| Column | Unit | Description |
|---|---|---|
| STUDYID | | Study identifier |
| USUBJID | | Unique subject identifier (must match the dosing file) |
| MATRIX | | `BLOOD`, `PLASMA` or `URINE` |
| SAMPLE_ID | | Lab sample ID (traceability only) |
| NOMINAL_START_H | h | Urine only: nominal start of the collection interval |
| NOMINAL_TIME_H | h | Blood/plasma: nominal sampling time. Urine: nominal end of collection. Pre-dose = 0 |
| SAMPLE_START_DATETIME | | Urine only: actual start of collection |
| SAMPLE_DATETIME | | Blood/plasma: actual sampling time. Urine: actual end of collection |
| URINE_VOLUME_ML | mL | Urine only: total voided volume of the interval |
| ALIQUOT_VOLUME_ML | mL | Volume of the counted aliquot |
| ALIQUOT_WEIGHT_G | g | Alternative to volume (converted with the matrix density in `config/config.yml`) |
| DILUTION_FACTOR | | Pre-dilution of the aliquot (1 = undiluted, 20 = 1:20) |
| COUNT_DATETIME | | Start of counting in the gamma counter |
| COUNT_TIME_MIN | min | Counting time |
| GROSS_COUNTS | counts | Gross counts in the nuclide window |
| BACKGROUND_CPM | cpm | Background count rate (blank tube) |
| CAL_CPM_PER_BQ | cpm/Bq | Counter calibration factor for the nuclide/window (= 60 x efficiency) |
| COMMENT | | Free text |

Conversion: `MBq/mL = (GROSS_COUNTS / COUNT_TIME_MIN - BACKGROUND_CPM) / CAL_CPM_PER_BQ * DILUTION_FACTOR / ALIQUOT_VOLUME_ML / 1e6`,
then decay-corrected from `COUNT_DATETIME` to `SAMPLE_DATETIME` (always) and optionally on to the
injection time (`decay_correction: to_injection` in the config).

If your counter already applies a decay correction (e.g. to a reference time), export the
**uncorrected** counts, otherwise the correction is applied twice.

## `dosing_template.csv` — one row per subject (single administration)

| Column | Unit | Description |
|---|---|---|
| STUDYID, USUBJID | | As above |
| SEX, AGE, WEIGHT_KG | | Demographics (carried into the ADNCA file) |
| NUCLIDE | | e.g. `Lu-177` (informational; the half-life used is the one in the config) |
| DRUG | | Radiopharmaceutical name (DOSETRT) |
| INJECTION_DATETIME | | Start of injection = time zero |
| INFUSION_DURATION_MIN | min | 0 for bolus |
| SYRINGE_PRE_MBQ / _DATETIME | MBq | Dose-calibrator reading of the full syringe and its time |
| SYRINGE_RESIDUAL_MBQ / _DATETIME | MBq | Residual activity after injection and its time (empty = 0) |

Dose (net injected activity at injection time) =
`SYRINGE_PRE_MBQ` decay-corrected to injection − `SYRINGE_RESIDUAL_MBQ` decay-corrected to injection.
