# Building `docs/PK_inputs_parameters_formulas.docx`

1. `npm install docx@9.5.1` (in any folder outside the repo), then
   `node docs/build/make_doc.js <path>/base.docx` — writes the document with a `[[TOC]]` placeholder.
2. Open `base.docx` in Word, replace `[[TOC]]` with a table of contents
   (References → Table of Contents, levels 1–2) and save as `docs/PK_inputs_parameters_formulas.docx`.

The table of contents is inserted by Word (step 2) so that readers do not get an
"update fields" prompt when opening the document.
