// Generates docs/PK_inputs_parameters_formulas.docx for the onc-pknca repository.
const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType, ShadingType,
  HeadingLevel, AlignmentType, PageOrientation, LevelFormat, Header, Footer, PageNumber,
  BorderStyle, VerticalAlign,
} = require("docx");

const OUT = process.argv[2];

// ---------- styling helpers ----------
const FONT = "Calibri";
const MATH = "Cambria Math";
const C_HEAD = "1F3864";
const C_SHADE = "D9E2F3";
const C_NOTE = "FFF2CC";
const BORDER = { style: BorderStyle.SINGLE, size: 4, color: "8EAADB" };
const BORDERS = { top: BORDER, bottom: BORDER, left: BORDER, right: BORDER };

// Inline markup: **bold**, `code`, $formula$ (Cambria Math, with _{sub} and ^{sup})
function runs(text, base = {}) {
  const out = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`|\$[^$]+\$)/g;
  let last = 0, m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push(new TextRun({ text: text.slice(last, m.index), ...base }));
    const tok = m[0];
    if (tok.startsWith("**")) out.push(new TextRun({ text: tok.slice(2, -2), bold: true, ...base }));
    else if (tok.startsWith("`")) out.push(new TextRun({ text: tok.slice(1, -1), font: "Consolas", ...base, size: (base.size || 20) - 2 }));
    else out.push(...mathRuns(tok.slice(1, -1), base));
    last = m.index + tok.length;
  }
  if (last < text.length) out.push(new TextRun({ text: text.slice(last), ...base }));
  return out;
}
function mathRuns(f, base = {}) {
  const out = [];
  const re = /([_^])\{([^}]*)\}/g;
  let last = 0, m;
  while ((m = re.exec(f)) !== null) {
    if (m.index > last) out.push(new TextRun({ text: f.slice(last, m.index), font: MATH, ...base }));
    out.push(new TextRun({ text: m[2], font: MATH, ...base, subScript: m[1] === "_", superScript: m[1] === "^" }));
    last = m.index + m[0].length;
  }
  if (last < f.length) out.push(new TextRun({ text: f.slice(last), font: MATH, ...base }));
  return out;
}
const P = (text, opts = {}) => new Paragraph({ children: runs(text, opts.run || {}), spacing: { after: 120 }, ...opts.para });
const H1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(t)], spacing: { before: 240, after: 120 } });
const H2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(t)], spacing: { before: 200, after: 100 } });
const H3 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(t)], spacing: { before: 160, after: 80 } });
const B = (t, level = 0) => new Paragraph({ numbering: { reference: "bullets", level }, children: runs(t), spacing: { after: 60 } });
const F = (t) => new Paragraph({ children: mathRuns(t, { size: 22 }), indent: { left: 567 }, spacing: { before: 60, after: 100 } });

function cell(text, width, { header = false, shade, bold = false, size = 18 } = {}) {
  const parts = Array.isArray(text) ? text : String(text).split("\n");
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders: BORDERS,
    verticalAlign: VerticalAlign.TOP,
    shading: header ? { fill: C_SHADE, type: ShadingType.CLEAR, color: "auto" } : shade ? { fill: shade, type: ShadingType.CLEAR, color: "auto" } : undefined,
    margins: { top: 50, bottom: 50, left: 80, right: 80 },
    children: parts.map((p) => new Paragraph({ children: runs(p, { size, bold: header || bold }), spacing: { after: 30 } })),
  });
}
function table(widths, header, rows, opts = {}) {
  const total = widths.reduce((a, b) => a + b, 0);
  return new Table({
    width: { size: total, type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      new TableRow({ tableHeader: true, children: header.map((h, i) => cell(h, widths[i], { header: true, size: opts.size || 18 })) }),
      ...rows.map((r) => new TableRow({
        cantSplit: true,
        children: r.cells.map((c, i) => cell(c, widths[i], { shade: r.shade, bold: r.bold, size: opts.size || 18 })),
      })),
    ],
  });
}
const row = (...cells) => ({ cells });
const groupRow = (label, n) => ({ cells: [label, ...Array(n - 1).fill("")], shade: "EDEDED", bold: true });
const spacer = () => new Paragraph({ children: [], spacing: { after: 80 } });

// ---------- page setup (A4) ----------
const A4 = { width: 11906, height: 16838 };
const MARGIN = { top: 1134, bottom: 1134, left: 1134, right: 1134 };
const PORTRAIT_W = A4.width - 2268;    // 9638
const LANDSCAPE_W = A4.height - 2268;  // 14570

const header = new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [new TextRun({ text: "onc-pknca – PK inputs, parameters and formulas (draft)", size: 16, color: "7F7F7F" })] })] });
const footer = new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "Page ", size: 16, color: "7F7F7F" }), new TextRun({ children: [PageNumber.CURRENT], size: 16, color: "7F7F7F" }), new TextRun({ text: " of ", size: 16, color: "7F7F7F" }), new TextRun({ children: [PageNumber.TOTAL_PAGES], size: 16, color: "7F7F7F" })] })] });
const portrait = { page: { size: { width: A4.width, height: A4.height }, margin: MARGIN } };
const landscape = { page: { size: { width: A4.width, height: A4.height, orientation: PageOrientation.LANDSCAPE }, margin: MARGIN } };

// =====================================================================================================
// Section A: title, scope, conventions, input data (portrait)
// =====================================================================================================
const W = PORTRAIT_W;
const secA = [
  new Paragraph({ alignment: AlignmentType.LEFT, spacing: { after: 60 }, children: [new TextRun({ text: "Radiopharmaceutical Pharmacokinetics", bold: true, size: 40, color: C_HEAD })] }),
  new Paragraph({ spacing: { after: 240 }, children: [new TextRun({ text: "Input data, parameter definitions and formulas – onc-pknca (PKNCA 0.12.1 / aNCA 0.1.0)", size: 26, color: "404040" })] }),
  table([2600, W - 2600], ["Item", "Value"], [
    row("Document status", "Draft 0.1 – describes a **fit-for-purpose test setup**, not a validated system (21 CFR Part 11 validation out of scope)"),
    row("Date", "2026-10-27"),
    row("Repository", "github.com/Sp0ngy/onc-pknca, branch `feat/pknca-anca-test`"),
    row("Software", "R 4.6.1, PKNCA 0.12.1, aNCA 0.1.0 (versions locked in `renv.lock`)"),
    row("Scripts described", "`R/preprocess.R`, `R/run_nca.R`, `R/nca.R`, `R/functions.R`; configuration `config/config.yml`"),
    row("Analyte", "Total radioactivity (gamma counting: parent + radiolabelled metabolites + free nuclide)"),
  ]),
  spacer(),
  new Paragraph({ children: [new TextRun({ text: "Contents", bold: true, size: 24, color: C_HEAD })], spacing: { after: 60 } }),
  new Paragraph({ children: [new TextRun("[[TOC]]")] }),

  H1("0  Conventions"),
  B("**Concentrations** are delivered and reported **decay-corrected to the time of injection** (biological view). Physical half-life of Lu-177: 6.647 d = 159.528 h (config `nuclide: half_life`)."),
  B("**Reporting unit kBq/mL.** The protocol specifies MBq/mL. Values are reported in kBq/mL as delivered (decision of 2026-10-27); 1 MBq/mL = 1000 kBq/mL. Changing `units: conc` to `MBq/mL` in the configuration reports everything in MBq/mL without changing the input."),
  B("**Time** = hours after the **start of injection** (t = 0). Actual times are used for all calculations; nominal times only for labelling, pairing and summaries."),
  B("**Dose** = net injected activity at injection time (MBq; syringe residual already subtracted)."),
  B("**Protocol names first.** Section 2 lists the parameters by the protocol names; the PKNCA and CDISC (aNCA) names are given next to them, with a note where the terminology differs."),
  B("Every output table states the decay-correction mode in its first column (`DECAY_CORRECTION`)."),

  H1("1  Expected input data"),
  P("The analysis needs **two CSV files** per study (UTF-8, comma-separated, one header row, empty cell = not applicable). Templates: `templates/concentrations_template.csv` and `templates/dosing_concentrations_template.csv`. Real study data are stored in `data-raw/study/` (excluded from git) and referenced in `config/config.yml`."),

  H2("1.1  Concentration file – one row per sample"),
  table([2050, 780, 780, 780, 1250, W - 5640], ["Column", "Blood", "Plasma", "Urine", "Unit", "Content"], [
    row("STUDYID", "✔", "✔", "✔", "–", "Study identifier"),
    row("USUBJID", "✔", "✔", "✔", "–", "Unique participant identifier; must exist in the dosing file"),
    row("MATRIX", "BLOOD", "PLASMA", "URINE", "–", "Matrix code (exactly these values, case-insensitive)"),
    row("SAMPLE_ID", "✔", "✔", "✔", "–", "Laboratory sample ID (traceability)"),
    row("NOMINAL_START_H", "–", "–", "✔", "h", "Nominal start of the urine collection interval"),
    row("NOMINAL_TIME_H", "✔", "✔", "✔", "h", "Blood/plasma: nominal sampling time (pre-dose = 0). Urine: nominal **end** of the interval"),
    row("START_TIME_H", "–", "–", "✔", "h", "Actual start of the urine collection, hours after start of injection"),
    row("TIME_H", "✔", "✔", "✔", "h", "Blood/plasma: actual sampling time. Urine: actual **end** of the collection. Pre-dose samples negative"),
    row("CONC", "✔", "✔", "✔", "kBq/mL", "Decay-corrected radioactivity concentration. A number, or `BLQ`, `<LLOQ`, `BQL`, `<LOQ`, `<LOD`, `ND` for values below the limit of quantification; empty if not available"),
    row("URINE_VOLUME_ML", "–", "–", "✔", "mL", "Total voided urine volume of the collection interval"),
    row("COMMENT", "opt.", "opt.", "opt.", "–", "Free text"),
  ]),

  H2("1.2  Matrix-specific requirements"),
  H3("Whole blood"),
  B("One row per sampling time, including the pre-dose sample (`TIME_H` < 0, `CONC` = `BLQ` or 0)."),
  B("Enough samples in the terminal phase for λz: at least **3 quantifiable samples after Cmax**, ideally spanning ≥ 2 half-lives (span ratio ≥ 2)."),
  B("`START_TIME_H` and `URINE_VOLUME_ML` stay empty."),
  H3("Plasma"),
  B("Same structure as whole blood."),
  B("Plasma obtained from the **same blood draw** must carry the **same nominal time** (`NOMINAL_TIME_H`) as the whole-blood sample – the blood-to-plasma ratio is paired by participant and nominal time."),
  H3("Urine"),
  B("One row per **collection interval** (pooled urine of the interval), not per void."),
  B("`START_TIME_H` / `TIME_H` = actual start / end of the collection; `NOMINAL_START_H` / `NOMINAL_TIME_H` = nominal interval (e.g. 0 / 4)."),
  B("Intervals must be **complete, contiguous and non-overlapping** (end of one = start of the next); the first interval starts at injection (bladder voided before injection)."),
  B("`URINE_VOLUME_ML` = total volume of the interval (mandatory); `CONC` = concentration measured in the pooled interval sample."),
  B("For urine, decay correction refers to the **end** of the collection interval (activity keeps decaying in the bladder and container) – please confirm with the laboratory that the delivered values follow this convention."),
  B("BLQ urine concentrations count as 0 excreted activity (config `blq: rule_urine`)."),

  H2("1.3  Example (concentration file)"),
  table([1200, 1150, 900, 1050, 750, 750, 750, 750, 900, W - 8200], ["STUDYID", "USUBJID", "MATRIX", "SAMPLE_ID", "NOM_ START_H", "NOM_ TIME_H", "START_ TIME_H", "TIME_H", "CONC", "URINE_ VOL_ML"], [
    row("STUDY-001", "STUDY-001-001", "BLOOD", "S001-B-01", "", "0", "", "-0.33", "BLQ", ""),
    row("STUDY-001", "STUDY-001-001", "BLOOD", "S001-B-02", "", "0.0833", "", "0.0833", "1129.6", ""),
    row("STUDY-001", "STUDY-001-001", "PLASMA", "S001-P-02", "", "0.0833", "", "0.0833", "1786.4", ""),
    row("STUDY-001", "STUDY-001-001", "URINE", "S001-U-01", "0", "4", "0", "3.87", "8555.5", "108"),
    row("STUDY-001", "STUDY-001-001", "URINE", "S001-U-02", "4", "8", "3.87", "7.82", "2475.7", "193"),
  ], { size: 16 }),

  H2("1.4  Dosing file – one row per participant"),
  table([2400, 1100, 1100, W - 4600], ["Column", "Required", "Unit", "Content"], [
    row("STUDYID, USUBJID", "yes", "–", "As in the concentration file"),
    row("NET_INJECTED_MBQ", "yes", "MBq", "Net injected activity at injection time (syringe activity before injection minus residual, both decay-corrected to injection time)"),
    row("INFUSION_DURATION_MIN", "yes", "min", "0 = IV bolus (C0 back-extrapolated); > 0 = infusion (C0 = 0)"),
    row("SEX, AGE, WEIGHT_KG", "optional", "–, y, kg", "Demographics, carried into the analysis dataset"),
    row("NUCLIDE, DRUG", "optional", "–", "Informational; the half-life used is the one in the configuration"),
  ]),

  H2("1.5  Configuration file config/config.yml – settings relevant for the input"),
  table([3300, 1700, W - 5000], ["Setting", "Value", "Meaning"], [
    row("`input: format`", "concentrations", "Input = concentrations vs. time (alternative: raw gamma counter data, section 3.8)"),
    row("`input: conc_unit`", "kBq/mL", "Unit of the CONC column"),
    row("`input: decay_corrected_to_injection`", "true", "CONC is already decay-corrected to injection time"),
    row("`decay_correction: to_injection`", "true", "Analysis on decay-corrected data → biological t1/2e. `false` → effective half-life (correction removed by the script)"),
    row("`units: conc`", "kBq/mL", "Reporting unit for concentrations and AUC"),
    row("`nuclide: half_life`", "6.647 d", "Physical half-life (Lu-177)"),
    row("`blq: lloq`", "per matrix", "LLOQ in reporting units, compared with the as-sampled concentration; 0 if BLQ is only flagged as text"),
    row("`blq: rule` / `rule_urine`", "pre_zero_post_missing / zero", "Handling of BLQ values (section 3.2)"),
  ]),

  H2("1.6  Automatic input checks"),
  P("Preprocessing stops with an error message if: a required column is missing; MATRIX is not BLOOD/PLASMA/URINE; a participant has no dosing record or more than one; urine rows lack start time or volume; TIME_H is missing; CONC contains text other than the BLQ codes; the net injected activity is missing or ≤ 0."),
];

// =====================================================================================================
// Section B: parameter table (landscape)
// =====================================================================================================
const LW = LANDSCAPE_W;
const pw = [380, 2050, 3050, 1000, 1350, 1250, 2300, LW - 11380];
const secB = [
  H1("2  Parameters – definitions and mapping"),
  P("Protocol names are used first. **PKNCA** = parameter name in PKNCA; **CDISC/aNCA** = PPTESTCD shown by aNCA. “own” = calculated by our scripts because PKNCA has no (suitable) parameter. All values refer to total radioactivity, decay-corrected to injection time."),
  table(pw, ["#", "Protocol parameter", "Definition", "Unit (reported)", "PKNCA", "CDISC / aNCA", "Output file → column", "Note on terminology / implementation"], [
    groupRow("Whole blood (identical calculation for plasma)", 8),
    row("1", "Radioactivity concentration in whole blood per collection time", "Decay-corrected total radioactivity concentration at each actual sampling time, after BLQ handling", "kBq/mL (protocol: MBq/mL)", "– (input value)", "– (AVAL in ADNCA)", "`concentrations.csv` → AVAL; `concentration_summary.csv`", "Not an NCA parameter. Descriptive statistics per nominal time are provided."),
    row("2", "Maximum concentration (Cmax)", "Highest observed concentration", "kBq/mL", "cmax", "CMAX", "`nca_parameters.csv` → Cmax", "Observed value only – the back-extrapolated C0 of an IV bolus is never reported as Cmax (PKNCA would do so by default; handled in `R/nca.R`)."),
    row("3", "Tmax", "Actual time of Cmax", "h", "tmax", "TMAX", "`nca_parameters.csv` → Tmax", "First occurrence if Cmax occurs twice. After an IV bolus usually the first sample."),
    row("4", "AUC0-t", "Area under the concentration–time curve from injection to the last quantifiable concentration (Tlast)", "h·kBq/mL", "auclast", "AUCLST", "`nca_parameters.csv` → AUC0-t", "PKNCA term is **AUClast**: “t” = Tlast, not a fixed time point. Includes the segment 0 → first sample using the back-extrapolated C0 (IV bolus)."),
    row("5", "AUC0-inf", "AUC0-t plus extrapolation to infinity", "h·kBq/mL", "aucinf.obs", "AUCIFO", "`nca_parameters.csv` → AUC0-inf", "“obs”: extrapolated with the **observed** Clast. PKNCA also offers aucinf.pred (predicted Clast) – not used."),
    row("6", "kel", "Terminal elimination rate constant: negative slope of ln C vs. t in the terminal phase", "1/h", "lambda.z", "LAMZ", "`nca_parameters.csv` → lambda_z (kel)", "PKNCA/CDISC name **λz**. Strictly, “kel” is the one-compartment elimination constant; here it is the terminal-phase constant (as defined in the protocol)."),
    row("7", "t1/2e", "Terminal elimination half-life", "h", "half.life", "LAMZHL", "`nca_parameters.csv` → t1/2", "Decay-corrected data → **biological** half-life. In nuclear medicine “Te” often means *effective* half-life – here “e” = elimination (protocol definition)."),
    row("8", "CL", "Total clearance of total radioactivity", "L/h", "cl.obs", "CLO", "`nca_parameters.csv` → CL", "Based on AUC0-inf (obs). IV administration → no bioavailability term. Clearance of total radioactivity, not of the parent compound."),
    row("9", "Vz", "Volume of distribution in the terminal phase", "L", "vz.obs", "VZO", "`nca_parameters.csv` → Vz", "Based on λz and AUC0-inf (obs)."),
    row("10", "Ratio of whole blood-to-plasma radioactivity at each time point / per participant", "Whole-blood concentration divided by plasma concentration of the same draw", "– (ratio)", "– (own)", "– (aNCA ratio tool only for parameters)", "`bp_ratio_individual.csv` → BP_RATIO; `bp_ratio_summary.csv`", "Paired by participant and nominal time; only if both values are quantifiable. Additionally: B:P ratio of AUC0-inf (section 3.4)."),
    groupRow("Urine", 8),
    row("11", "Radioactivity concentration per collection time", "Decay-corrected concentration in the pooled urine of each collection interval", "kBq/mL (protocol: MBq/mL)", "– (input value)", "– (AVAL)", "`urine_intervals.csv` → AVAL", "“Collection time” = collection **interval** (start–end), see columns NFRLT/NAEFRLT and AFRLT/AEFRLT."),
    row("12", "Ae interval", "Amount of radioactivity excreted in one collection interval", "MBq", "– (own: C × V)", "RCAMINT (per interval)", "`urine_intervals.csv` → AE", "PKNCA’s `ae` over [start, end] also picks up the adjacent collection (inclusive interval bounds) – therefore calculated directly. aNCA 0.1.0 is affected by this (per-interval Ae 1.5–3× too high)."),
    row("13", "TRmax", "Time of the maximum urinary excretion rate = midpoint of the collection interval with Rmax", "h", "– (own)", "TRMAX", "`urine_rmax.csv` → TRMAX", "Not available in PKNCA 0.12.1. Midpoint of **actual** times; the nominal interval is reported alongside."),
    row("14", "Rmax", "Maximum urinary excretion rate (Ae interval / interval duration)", "MBq/h", "– (own)", "RMAX", "`urine_rmax.csv` → RMAX", "Not available in PKNCA 0.12.1. Based on the rate, not on Ae – a long interval can contain more Ae at a lower rate."),
    row("15", "Ae0-t", "Cumulative amount excreted from injection to the end of collection t", "MBq", "ae (interval 0 → t)", "RCAMINT (0–t)", "`urine_intervals.csv` → AE_CUM; `renal_clearance.csv` → AE_CUM (t = end of last collection)", "t = end of a collection interval (reported for each; overall e.g. 0–96 h). PKNCA value cross-checked against the running sum of Ae interval."),
    row("16", "%Fe0-t", "Cumulative fraction of the injected activity excreted in urine, in %", "%", "fe (× 100)", "FREXINT", "`urine_intervals.csv` → FE_CUM_PCT", "PKNCA `fe` is a fraction (0–1); reported × 100. Per interval: FE_PCT. In aNCA with kBq/mL shown as kBq/MBq (× 0.1 = %)."),
  ], { size: 16 }),
  spacer(),
  H2("2.1  Additional parameters calculated (not requested in the protocol)"),
  table([3000, 1300, 1500, 1500, LW - 7300], ["Parameter", "Unit", "PKNCA", "CDISC / aNCA", "Purpose"], [
    row("%AUCextrap (AUC %extrap)", "%", "aucpext.obs", "AUCPEO", "Quality of AUC0-inf; flagged if > 20 %"),
    row("R², adjusted R² of λz regression", "–", "r.squared, adj.r.squared", "R2, R2ADJ", "Quality of kel; flagged if adj. R² < 0.9"),
    row("Number of points / start time of λz regression", "– / h", "lambda.z.n.points, lambda.z.time.first", "LAMZNPT, LAMZLL", "Documentation of the terminal phase selection"),
    row("Span ratio", "–", "span.ratio", "–", "Time span of the regression in half-lives; flagged if < 2"),
    row("Clast, Tlast", "kBq/mL, h", "clast.obs, tlast", "CLST, TLST", "Last quantifiable concentration and its time"),
    row("fe per interval (FE_PCT)", "%", "– (own)", "FREXINT (per interval)", "Per-interval excretion"),
    row("Urinary excretion rate per interval (RATE) and midpoint", "MBq/h, h", "– (own)", "–", "Basis of Rmax/TRmax"),
    row("Renal clearance CLr", "L/h", "– (own; clr.* not usable across matrices)", "RENALCL", "Ae0-T / plasma AUC0-T"),
    row("B:P ratio of AUC0-inf", "–", "– (own)", "RAAUCIFO (aNCA ratio tool)", "Overall blood-to-plasma partitioning"),
  ]),
];

// =====================================================================================================
// Section C: formulas (landscape)
// =====================================================================================================
const fw = [2300, 5300, 4200, LW - 11800];
const FH = ["Quantity", "Implemented in our scripts", "Standard implementation / reference", "Note"];
const secC = [
  H1("3  Formulas"),
  P("Notation: $C$ = concentration, $t$ = actual time after start of injection (h), $λ_{p}$ = physical decay constant, $λ_{z}$ = terminal elimination rate constant (kel), $D$ = net injected activity (MBq), $ln$ = natural logarithm (base e). Where our implementation and the usual standard (PKNCA default, Phoenix WinNonlin, regulatory guidance) coincide, this is stated."),

  H2("3.1  Decay correction and units"),
  table(fw, FH, [
    row("Physical decay constant", "$λ_{p} = ln 2 / T_{1/2,phys}$ \n Lu-177: $λ_{p} = ln 2 / 159.528 h = 0.004345 h^{−1}$", "Same (physical law)", "`nuclide: half_life` in the configuration."),
    row("Decay correction (general)", "$A(t_{ref}) = A(t_{meas}) · exp(λ_{p} · (t_{meas} − t_{ref}))$", "Same", "Measurement later than reference → value increases."),
    row("As-sampled concentration from decay-corrected input", "$C_{sampled} = C_{dc} · exp(−λ_{p} · t)$ \n t = sampling time; urine: end of collection", "Same", "Used for the BLQ decision and for the effective mode only."),
    row("Reported concentration", "decay correction on: $C = C_{dc}$ (biological view) \n off: $C = C_{sampled}$ (effective view)", "–", "Default: on. Every output states the mode."),
    row("Unit conversion", "$C [units:conc] = CONC [input unit] × f$, e.g. kBq/mL → MBq/mL: $f = 10^{−3}$", "Same", "R package `units` (udunits)."),
    row("Biological vs. effective rate constant", "$λ_{z,eff} = λ_{z,bio} + λ_{p}$ ; $1/T_{1/2,eff} = 1/T_{1/2,bio} + 1/T_{1/2,phys}$", "Same (standard relation, MIRD)", "Exact for identical regression points; the automatic point selection may differ between modes."),
  ]),

  H2("3.2  BLQ handling (per participant and matrix, in time order)"),
  table(fw, FH, [
    row("BLQ decision", "BLQ if $C_{sampled} < LLOQ$ or CONC reported as BLQ text", "LLOQ applies to the measured (as-sampled) value", "Decay correction cannot lift a non-quantifiable value above the LLOQ."),
    row("Rule blood/plasma (default `pre_zero_post_missing`)", "BLQ before first quantifiable value → 0; BLQ after it → missing (excluded)", "Common default (PKNCA default `conc.blq`: first = keep as 0, middle/last = drop or keep)", "Alternatives: `zero`, `missing`, `half_lloq` (after first quantifiable value → LLOQ/2)."),
    row("Rule urine (default `zero`)", "BLQ → 0 (interval contributes 0 to Ae)", "Common practice", ""),
  ]),

  H2("3.3  Blood and plasma NCA (PKNCA, options set in `R/nca.R`)"),
  table(fw, FH, [
    row("Cmax, Tmax", "$C_{max} = max(C_{i})$ over observed values, $T_{max}$ = its time (first if tied)", "Same (PKNCA, WinNonlin)", "Imputed C0 excluded (separate calculation set)."),
    row("Clast, Tlast", "Last concentration > 0 and its time", "Same", ""),
    row("C0 (IV bolus only, used only for AUC-based parameters)", "$C_{0} = exp(ln C_{1} − (ln C_{2} − ln C_{1})/(t_{2} − t_{1}) · t_{1})$ = $C_{1} · (C_{1}/C_{2})$ to the power $t_{1}/(t_{2} − t_{1})$ \n (t1, C1), (t2, C2) = first two samples after dose, requires $C_{2} < C_{1}$ \n Infusion: $C(0) = 0$", "Log-linear back-extrapolation from the first two points (WinNonlin; PKNCA `pk.calc.c0(method = \"logslope\")`). WinNonlin falls back to C0 = C1 if not declining.", "If the first two values do not decline, no C0 is imputed and AUC0-t is not calculated – check such profiles manually."),
    row("AUC segment (lin-up/log-down)", "falling ($C_{i+1} < C_{i}$, $C_{i+1} > 0$): $(C_{i} − C_{i+1}) · (t_{i+1} − t_{i}) / ln(C_{i}/C_{i+1})$ \n rising or constant: $(C_{i} + C_{i+1})/2 · (t_{i+1} − t_{i})$ \n both 0: 0", "PKNCA default `auc.method = \"lin up/log down\"`. Alternative: linear trapezoidal for all segments (described in FDA/EMA bioequivalence guidance).", "AUC integrates C, not ln C; ln only shapes the interpolation of falling segments. State the method in the SAP."),
    row("AUC0-t", "$AUC_{0−t} = Σ$ segments from 0 to Tlast", "Same", ""),
    row("kel (λz)", "Fit $ln C = a − λ_{z} · t$ (least squares) on the last n points, n = 3, 4, …, only points with C > 0 and t > Tmax", "Same (WinNonlin “best fit”; PKNCA)", "Points can be fixed manually in aNCA (Slope Selector)."),
    row("R², adjusted R²", "$R^{2} = 1 − Σ residuals^{2} / Σ (ln C − mean ln C)^{2}$ \n $R^{2}_{adj} = 1 − (1 − R^{2}) · (n − 1)/(n − 2)$", "Same", ""),
    row("Selection of λz points", "λz > 0 and $R^{2}_{adj} > max R^{2}_{adj} − 0.0001$; among these, the largest n", "Same rule as WinNonlin best fit and PKNCA default (`adj.r.squared.factor` = 1e-4)", "Data-driven: may use few points when data are very clean."),
    row("t1/2e", "$t_{1/2} = ln 2 / λ_{z}$", "Same", "Biological if decay-corrected."),
    row("Span ratio", "(last − first time of the λz points) / $t_{1/2}$", "Same (PKNCA)", "Flag if < 2."),
    row("AUC0-inf", "$AUC_{0−∞} = AUC_{0−t} + C_{last,obs} / λ_{z}$", "Same (“obs”); alternative uses predicted Clast (“pred”)", ""),
    row("%AUCextrap", "$100 · (1 − AUC_{0−t} / AUC_{0−∞})$", "Same", "Flag if > 20 %."),
    row("CL", "$CL = D / AUC_{0−∞}$ ; MBq / (h·kBq/mL) = L/h", "Same (IV: no F)", ""),
    row("Vz", "$V_{z} = CL / λ_{z} = D / (λ_{z} · AUC_{0−∞})$ ; MBq / (kBq/mL) = L", "Same", ""),
    row("Quality flags", "AUC %extrap > 20 %; adj. R² < 0.9; span ratio < 2; λz not estimable", "Typical acceptance criteria (aNCA default adj. R² ≥ 0.7)", "Values are flagged, never deleted."),
  ], { size: 16 }),

  H2("3.4  Blood-to-plasma ratios"),
  table(fw, FH, [
    row("Per time point and participant", "$B:P = C_{blood} / C_{plasma}$ (same participant, same nominal time), only if both > 0", "Same", ""),
    row("AUC-based", "$AUC_{0−∞,blood} / AUC_{0−∞,plasma}$ per participant", "Same", "Check direction in aNCA ratio tool (test = BLOOD, reference = PLASMA)."),
  ]),

  H2("3.5  Urine"),
  table(fw, FH, [
    row("Ae interval", "$Ae_{i} = C_{urine,i} · V_{urine,i}$ (C converted to MBq/mL)", "Same (sum of concentration × volume)", "PKNCA `ae` not used per interval (inclusive interval bounds)."),
    row("fe interval", "$fe_{i} = 100 · Ae_{i} / D$ [%]", "Same", ""),
    row("Ae0-t", "$Ae_{0−t} = Σ Ae_{j}$ over all intervals with $t_{end,j} ≤ t$ (PKNCA `ae`, time = end of collection, interval [0, t])", "Same", "Checked against the running sum of Ae interval."),
    row("%Fe0-t", "$\%Fe_{0−t} = 100 · Ae_{0−t} / D$ (PKNCA `fe` × 100)", "Same", ""),
    row("Excretion rate per interval", "$R_{i} = Ae_{i} / (t_{end,i} − t_{start,i})$ [MBq/h], at $t_{mid,i} = (t_{start,i} + t_{end,i})/2$", "Same (WinNonlin urine model: rate at interval midpoint)", "Actual times."),
    row("Rmax, TRmax", "$R_{max} = max(R_{i})$ ; $TR_{max} = t_{mid}$ of that interval (first if tied)", "Same (CDISC RMAX, TRMAX = midpoint)", "Not in PKNCA 0.12.1."),
    row("Renal clearance (additional)", "$CL_{R} = Ae_{0−T} / AUC_{plasma,0−T}$, T = end of last collection; plasma AUC with same C0 and lin-up/log-down; C(T) interpolated: falling segment $C(T) = exp(ln C_{i} + (T − t_{i})/(t_{i+1} − t_{i}) · (ln C_{i+1} − ln C_{i}))$, otherwise linear", "Same definition; PKNCA `aucint.*` ignores the C0 imputation and is therefore not used", ""),
  ], { size: 16 }),

  H2("3.6  Descriptive statistics"),
  table(fw, FH, [
    row("Arithmetic", "N (non-missing); mean $= Σx/N$; SD with $N − 1$; $CV\% = 100 · SD / mean$; median, min, max", "Same", ""),
    row("Geometric", "$geomean = exp(mean(ln x))$; $geoCV\% = 100 · \√(exp(s^{2}) − 1)$, s = SD of ln x; positive values only", "Same", "Usual for AUC, Cmax, CL."),
  ]),

  H2("3.7  Dose"),
  table(fw, FH, [
    row("Net injected activity", "Input `NET_INJECTED_MBQ` (format concentrations) \n gamma counts format: $D = A_{pre} · exp(λ_{p} · (t_{pre} − t_{inj})) − A_{res} · exp(λ_{p} · (t_{res} − t_{inj}))$", "Same", "Both syringe readings decay-corrected to injection time."),
  ]),

  H2("3.8  Alternative input: raw gamma counter data (format `gamma_counts`)"),
  table(fw, FH, [
    row("Net count rate", "$net cpm = counts / t_{count} − background cpm$", "Same", ""),
    row("Activity", "$A [Bq] = net cpm / calibration factor [cpm/Bq]$", "Same (efficiency-corrected)", "No dead-time correction."),
    row("Concentration at counting", "$C = A · dilution / V_{aliquot} / 10^{6}$ [MBq/mL]; $V_{aliquot} = weight / density$ if not pipetted", "Same", ""),
    row("Back to sampling / injection", "$C_{sampled} = C_{count} · exp(λ_{p} · (t_{count} − t_{sample}))$, then optionally $× exp(λ_{p} · t_{sample})$", "Same", "Counter must not have applied its own decay correction."),
  ]),
  spacer(),
  P("Verification: the formulas are covered by automated tests (`tests/testthat`, 92 checks), including a hand-calculated reference profile (Cmax, λz, AUC, CL, Vz agree to 10⁻¹⁰), urine Ae/fe/Rmax/TRmax with hand-calculated values, and an equivalence check of both input formats with and without decay correction. aNCA 0.1.0 reproduces the blood/plasma parameters exactly (`tests/check_anca.R`).", { run: { size: 18, italics: true } }),
];

const doc = new Document({
  creator: "onc-pknca",
  title: "Radiopharmaceutical PK – inputs, parameters and formulas",
  styles: {
    default: { document: { run: { font: FONT, size: 20 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 30, bold: true, color: C_HEAD, font: FONT }, paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 24, bold: true, color: "2F5496", font: FONT }, paragraph: { spacing: { before: 200, after: 100 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 21, bold: true, color: "404040", font: FONT }, paragraph: { spacing: { before: 140, after: 60 }, outlineLevel: 2 } },
    ],
  },
  numbering: { config: [{ reference: "bullets", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 567, hanging: 283 } } } }, { level: 1, format: LevelFormat.BULLET, text: "–", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 1134, hanging: 283 } } } }] }] },

  sections: [
    { properties: portrait, headers: { default: header }, footers: { default: footer }, children: secA },
    { properties: landscape, headers: { default: header }, footers: { default: footer }, children: secB },
    { properties: landscape, headers: { default: header }, footers: { default: footer }, children: secC },
  ].filter((_, i) => !process.env.ONLY || process.env.ONLY.split(",").includes(String(i))),
});

Packer.toBuffer(doc).then((buf) => {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, buf);
  console.log("wrote", OUT);
});
