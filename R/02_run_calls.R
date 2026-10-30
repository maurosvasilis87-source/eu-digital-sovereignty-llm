# ---------------------------------------------------------------------------
# 02_run_calls.R  -  sends the passages to the model and logs every call
#
# Run from the project root, in this order, changing MODE each time:
#
#   MODE <- "check"  one live call on one pilot passage: is the key working,
#                    and what does a raw response look like? Writes nothing.
#   MODE <- "pilot"  Prompts A and B on 8 paragraphs from the AI Continent
#                    Action Plan, to catch wording problems BEFORE you freeze
#                    the prompts. Writes data/pilot_log.csv, which the report
#                    never reads.
#   MODE <- "run"    the real thing: your 30 passages, every run in RUNS.
#                    Writes data/calls_log.csv. Needs your finished labels.
#
# then:  source("R/02_run_calls.R")
#
# Your key stays in .Renviron (Week 5). It never appears here.
#
# Why not parallel_chat_structured() as in Week 6: it returns only the parsed
# labels, and the guide asks for the raw responses. One call at a time also
# gives each call its own timestamp, and the log is written after every call,
# so an interrupted run resumes where it stopped instead of starting over.
# ---------------------------------------------------------------------------

library(ellmer)
library(readr)
library(dplyr)
library(jsonlite)

MODE <- if (exists("MODE")) MODE else "check"

MODEL <- "gpt-5.6-luna"          # the course model. Temperature is left at the
                                 # provider default: this model refuses any
                                 # other value (Week 6, section 6.2.8).
RUNS  <- c(A  = "prompt_a",      # the measurement
           B  = "prompt_b",      # THE comparison: reworded prompt
           A2 = "prompt_a")      # Prompt A again, nothing changed: how much
                                 # moves by chance alone. Delete this line if
                                 # you decide against it.
N_PER_DOC <- 15
N_PILOT   <- 8

source("R/prompts.R")

if (any(grepl("[TIE-BREAK]", c(prompt_a, prompt_b), fixed = TRUE)) &&
    MODE != "check") {
  stop("Write your tie-break rule into both prompts in R/prompts.R first.")
}
if (!nzchar(Sys.getenv("OPENAI_API_KEY"))) {
  stop("No OPENAI_API_KEY found. Add it to .Renviron (Week 5) and restart R.")
}

# ---------------------------------------------------------------------------
# One call, fully recorded
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Fingerprint of the prompts file, stored with every call. The report computes
# the same fingerprint and warns if the prompts were edited after the run.
# Line endings are normalised first, so Git on Windows cannot change it.
prompt_hash <- function(path) {
  tf <- tempfile(); con <- file(tf, "wb")
  writeLines(readLines(path, warn = FALSE), con, sep = "\n"); close(con)
  unname(tools::md5sum(tf))
}

call_one <- function(run, pid, text, system_prompt) {
  # A fresh chat for every passage, so no passage is judged in the context of
  # another (Week 5, section 5.3.3).
  chat <- chat_openai(system_prompt = system_prompt, model = MODEL,
                      echo = "none")
  t0 <- Sys.time()
  parsed <- tryCatch(chat$chat_structured(text, type = type_frame),
                     error = function(e) e)
  t1 <- Sys.time()

  turn <- tryCatch(chat$last_turn(), error = function(e) NULL)
  json <- tryCatch(turn@json, error = function(e) NULL)
  toks <- tryCatch(as.numeric(turn@tokens), error = function(e) c(NA, NA))

  ok <- !inherits(parsed, "error") && !is.null(parsed$frame) &&
    length(parsed$frame) == 1 && !is.na(parsed$frame)

  tibble(
    run             = run,
    pid             = pid,
    model_requested = MODEL,
    model_returned  = as.character(json$model %||% NA_character_),
    started_at      = format(t0, "%Y-%m-%d %H:%M:%OS2 %Z"),
    seconds         = round(as.numeric(difftime(t1, t0, units = "secs")), 2),
    temperature     = "provider default (not settable on this model)",
    frame           = if (ok) as.character(parsed$frame) else NA_character_,
    parse_ok        = ok,
    error           = if (inherits(parsed, "error"))
                        conditionMessage(parsed) else NA_character_,
    input_tokens    = toks[1],
    output_tokens   = toks[2],
    raw_response    = if (is.null(json)) NA_character_ else
                        as.character(toJSON(json, auto_unbox = TRUE,
                                            null = "null", digits = NA)),
    prompt_md5      = prompt_hash("R/prompts.R"),
    ellmer_version  = as.character(packageVersion("ellmer")),
    r_version       = R.version.string
  )
}

# Runs every (run, passage) pair not already in the log, appending as it goes.
run_set <- function(items, runs, log_file) {
  done <- if (file.exists(log_file)) {
    read_csv(log_file, show_col_types = FALSE,
             col_types = cols(.default = col_character())) |>
      filter(parse_ok == "TRUE") |>
      transmute(key = paste(run, pid))
  } else tibble(key = character())

  todo <- tidyr::expand_grid(run = names(runs), pid = items$pid) |>
    filter(!paste(run, pid) %in% done$key)
  message(nrow(todo), " calls to make (", nrow(done), " already logged).")

  for (i in seq_len(nrow(todo))) {
    r   <- todo$run[i]
    row <- items[items$pid == todo$pid[i], ]
    out <- call_one(r, row$pid, row$text, get(runs[[r]]))
    write_csv(out, log_file, append = file.exists(log_file))
    message(sprintf("[%d/%d] %s %s -> %s", i, nrow(todo), r, row$pid,
                    ifelse(out$parse_ok, out$frame, paste("FAILED:", out$error))))
  }
  invisible(read_csv(log_file, show_col_types = FALSE))
}

# ---------------------------------------------------------------------------
# The three modes
# ---------------------------------------------------------------------------

if (MODE == "check") {
  pilot <- read_csv("data/pilot_pool.csv", show_col_types = FALSE)
  out <- call_one("check", pilot$pid[1], pilot$text[1],
                  sub("[TIE-BREAK]", "", prompt_a, fixed = TRUE))
  cat("\nParsed label :", out$frame,
      "\nModel served :", out$model_returned,
      "\nSeconds      :", out$seconds,
      "\nError        :", out$error,
      "\n\nRaw response (first 600 characters):\n",
      substr(out$raw_response, 1, 600), "\n")
}

if (MODE == "pilot") {
  pilot <- read_csv("data/pilot_pool.csv", show_col_types = FALSE) |>
    arrange(draw_order) |> slice_head(n = N_PILOT)
  log <- run_set(pilot, RUNS[c("A", "B")], "data/pilot_log.csv")
  # Read these. Where A and B differ, is the wording to blame?
  log |> select(run, pid, frame) |>
    tidyr::pivot_wider(names_from = run, values_from = frame) |>
    left_join(select(pilot, pid, text), by = "pid") |>
    mutate(text = substr(text, 1, 120)) |> print(n = Inf, width = Inf)
}

if (MODE == "run") {
  pool  <- read_csv("data/pool.csv", show_col_types = FALSE)
  # The labelling sheet, as an Excel file (read directly, so no CSV
  # conversion and no semicolon problems from Dutch Excel settings)
  sheet <- readxl::read_excel("data/labelling_sheet.xlsx", col_types = "text")

  # Your 30: the first 15 included passages per document, in draw order.
  # "Y" and "YES" both count as included.
  items <- sheet |>
    mutate(draw_order = as.integer(draw_order),
           include    = substr(toupper(trimws(include)), 1, 1),
           label      = toupper(trimws(label))) |>
    filter(include %in% "Y") |>
    group_by(doc) |> arrange(draw_order, .by_group = TRUE) |>
    slice_head(n = N_PER_DOC) |> ungroup() |>
    select(pid, doc, label) |>
    left_join(select(pool, pid, text), by = "pid")   # text from pool.csv

  n_inc <- table(factor(items$doc, levels = c("COM", "JOIN")))
  if (any(n_inc != N_PER_DOC))
    stop("Included passages so far: COM ", n_inc[["COM"]], ", JOIN ",
         n_inc[["JOIN"]], ". Need ", N_PER_DOC, " in each: keep screening.")
  bad <- items$pid[!items$label %in% c("SECURITY", "ECONOMIC", "RIGHTS")]
  if (length(bad))
    stop("Each included passage needs exactly one label (SECURITY, ECONOMIC ",
         "or RIGHTS). Fix: ", paste(bad, collapse = ", "))

  run_set(items, RUNS, "data/calls_log.csv")
  message("Done. Commit data/calls_log.csv; the report reads it from there.")
}
