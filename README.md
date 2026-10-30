# Can AI reliably identify the political framings of EU digital sovereignty?

Final project, Applied AI for Political Scientists (Track B), Vasileios Mavros.

An LLM (`gpt-5.6-luna`, via `ellmer`) classifies 30 hand-labelled passages from
two EU documents as SECURITY, ECONOMIC or RIGHTS framings; the check rewords the
prompt and holds everything else fixed.

## Files

| Path | What it is |
|---|---|
| `data-raw/JOIN_2025_140.pdf` | JOIN(2025) 140 final, *An International Digital Strategy for the EU* |
| `data-raw/COM_2026_503.pdf` | COM(2026) 503 final, *European Tech Sovereignty*, main text |
| `R/01_build_pool.R` | PDFs → `data/pool.csv` (every body paragraph of 40+ words, footnotes removed, seeded draw order) and the blank labelling sheet, which I converted to `data/labelling_sheet.xlsx` |
| `R/prompts.R` | The schema and Prompts A and B, verbatim |
| `R/02_run_calls.R` | Sends the passages, one fresh chat per call, logs everything to `data/calls_log.csv` |
| `data/labelling_sheet.xlsx` | Screening decisions and hand labels, made before any model call |
| `data/calls_log.csv` | One row per API call: timestamp, model requested and served, tokens, parsed label, errors, raw JSON response |
| `Mavros_Vasilis_FinalProject.Rmd` | The report (submitted on Brightspace). Reads the files in this repository; makes no API calls |

## Order

1. `R/01_build_pool.R` (already run; do not re-run once labelling has started,
   since a different poppler version could split paragraphs differently).
2. Screen and label in `data/labelling_sheet.xlsx`, working down each document
   in `draw_order` until 15 per document pass the screen. Commit.
3. Write the tie-break rule into both prompts in `R/prompts.R`.
4. `R/02_run_calls.R` with `MODE <- "check"`, then `"pilot"`, then freeze the
   prompts, then `"run"`. Commit `data/calls_log.csv`.
5. Knit the report from a clean R session.

The API key lives in `.Renviron`, which is never committed.
