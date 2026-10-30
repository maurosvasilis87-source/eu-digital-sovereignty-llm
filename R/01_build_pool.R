# ---------------------------------------------------------------------------
# 01_build_pool.R
#
# Turns the two policy documents into a pool of candidate passages, puts each
# document's pool in a random order fixed by a seed, and writes the sheet you
# label by hand.
#
# Run once, from the project root (the folder that contains R/ and data/):
#   source("R/01_build_pool.R")
#
# Inputs  (data-raw/):  JOIN_2025_140.pdf, COM_2026_503.pdf,
#                       COM_2025_165_pilot.pdf (optional, pilot only)
# Outputs (data/):      pool.csv            every candidate passage, never edit
#                       labelling_sheet.csv the sheet you fill in by hand
#                       pilot_pool.csv      AI Continent paragraphs, pilot only
#
# No API calls here, and nothing random except the seeded draw order.
# ---------------------------------------------------------------------------

library(pdftools)
library(dplyr)
library(stringr)
library(readr)

set.seed(2026)

# ---------------------------------------------------------------------------
# Decisions. Each of these could have gone otherwise; report them.
# ---------------------------------------------------------------------------

BODY_MIN_PT <- 11.5  # body text is 12pt; footnotes (10pt), superscript markers
                     # (6.5-8pt) and page numbers (11pt) fall below this and are
                     # dropped. Footnote text is therefore never part of a passage.
LINE_TOL    <- 4     # words within 4pt vertically are on the same line
PARA_GAP    <- 18    # a vertical gap above 18pt starts a new paragraph
                     # (line spacing is 13-14pt; paragraph gaps are 20-30pt)
MIN_WORDS   <- 40    # shorter units (headings, lead-ins, one-line bullets)
                     # are not candidates
# a list item starts with a bullet glyph, a spaced dash, or "a)", "iv)", "2)"
BULLET_RX   <- "^(•||▪|(-|–)\\s|\\(?[a-z]\\)\\s|\\(?[ivx]+\\)\\s|[0-9]+\\)\\s)"

docs <- tibble::tribble(
  ~doc,   ~file,                           ~first_page, ~last_page,
  "JOIN", "data-raw/JOIN_2025_140.pdf",    2,           NA,   # p.1 is the cover
  "COM",  "data-raw/COM_2026_503.pdf",     2,           NA    # p.1 is the cover
)
# Pages are PDF pages. In both documents the printed page numbers run one
# behind (PDF p.2 is printed "1"): subtract one when citing a printed page.

# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

# One row per line of body text, with its page and vertical position.
pdf_lines <- function(file, first_page, last_page) {
  pages <- pdf_data(file, font_info = TRUE)
  if (is.na(last_page)) last_page <- length(pages)

  out <- vector("list", last_page - first_page + 1)
  for (p in first_page:last_page) {
    w <- pages[[p]]
    w <- w[!is.na(w$font_size), ]
    is_body <- w$font_size >= BODY_MIN_PT & w$font_size < 14   # 14+ is title type
    # The JOIN sets headings in bold small capitals, whose small letters are
    # 9.5pt. Keep those, but only on a line that also has full-size bold type.
    bold_body_y <- w$y[is_body & str_detect(w$font_name, "Bold")]
    is_small_caps <- !is_body & w$font_size >= 9 &
      str_detect(w$font_name, "Bold") &
      vapply(w$y, function(y) any(abs(bold_body_y - y) <= 3), logical(1))
    w <- w[is_body | is_small_caps, ]
    if (nrow(w) == 0) next
    w <- w[order(w$y, w$x), ]

    # cluster words into lines
    line_id <- cumsum(c(TRUE, diff(w$y) > LINE_TOL))
    w$line  <- line_id

    lines <- w |>
      group_by(line) |>
      arrange(x, .by_group = TRUE) |>
      mutate(
        # a space follows a word if the PDF says so or if there is a visible
        # gap before the next word (the PDF's own flag is lost at font changes)
        gap_after = lead(x) - (x + width),
        sep = ifelse(space | (!is.na(gap_after) & gap_after > 1), " ", "")
      ) |>
      summarise(
        y      = min(y),
        x1     = max(x + width),                 # right edge of the line
        bold   = mean(str_detect(font_name, "Bold")),
        italic = mean(str_detect(font_name, "Italic")),
        text   = paste0(text, sep, collapse = ""),
        .groups = "drop"
      ) |>
      mutate(page = p, text = str_squish(text)) |>
      filter(!str_detect(text, "^[0-9]+$")) |>  # page numbers
      # justified body lines run to the right margin; headings stop short
      mutate(full_width = x1 > quantile(x1, 0.75) - 15)
    out[[p - first_page + 1]] <- lines
  }
  bind_rows(out)
}

# Join lines with a space, except after a line ending in a compound hyphen
# ("volunteer-" + "driven"). A suspended hyphen keeps its space
# ("energy-" + "and resource-efficient").
join_lines <- function(x) {
  if (length(x) == 1) return(x)
  sep <- ifelse(str_detect(x[-length(x)], "\\p{L}-$") &
                  !str_detect(x[-1], "^(and|or)\\b"), "", " ")
  paste0(c(paste0(x[-length(x)], sep), x[length(x)]), collapse = "")
}

# Lines into paragraphs: a new paragraph starts after a large vertical gap,
# at a bullet marker, or at the top of a page.
lines_to_paragraphs <- function(lines) {
  numbered_rx <- "^[0-9]+(\\.[0-9]+)*\\.?\\s+\\p{Lu}"
  lines <- lines |>
    group_by(page) |>
    mutate(
      gap   = y - lag(y),
      words = str_count(text, "\\S+"),
      # a heading line: short, not running to the right margin, set apart by
      # space above it (or following another heading), and bold, italic or
      # numbered. The space-above condition stops the bold last line of a
      # paragraph counting as one; the margin condition stops a bold first line.
      heading_line = words <= 12 & !full_width &
        (bold > 0.8 | italic > 0.8 | str_detect(text, numbered_rx)) &
        ((!is.na(gap) & gap > PARA_GAP) | str_detect(text, numbered_rx)),
      heading_line = heading_line |
        (words <= 12 & !full_width & (bold > 0.8 | italic > 0.8) &
           lag(heading_line, default = FALSE)),
      new = is.na(gap) | gap > PARA_GAP | str_detect(text, BULLET_RX) |
        heading_line | lag(heading_line, default = FALSE)
    ) |>
    ungroup() |>
    mutate(para = cumsum(new))

  paras <- lines |>
    group_by(para) |>
    summarise(
      page    = first(page),
      heading = all(heading_line),
      text    = join_lines(text),
      .groups = "drop"
    )

  # Paragraphs broken across a page: if the last paragraph of a page does not
  # end in terminal punctuation, glue the first paragraph of the next page to
  # it (unless that one is a new bullet or a heading).
  i <- 1
  while (i < nrow(paras)) {
    is_last_on_page  <- paras$page[i + 1] == paras$page[i] + 1
    ends_open        <- !str_detect(paras$text[i], "[.:;!?]\\W*$")
    next_is_new      <- str_detect(paras$text[i + 1], BULLET_RX) |
      paras$heading[i + 1] | paras$heading[i]
    if (is_last_on_page && ends_open && !next_is_new) {
      paras$text[i] <- join_lines(c(paras$text[i], paras$text[i + 1]))
      paras <- paras[-(i + 1), ]
    } else {
      i <- i + 1
    }
  }

  paras |>
    mutate(
      # neither document hyphenates at line breaks, so hyphens are left alone
      # ("energy- and resource-efficient" is the source's own spelling)
      text  = str_replace(text, "^(•||▪)\\s*", "• "),
      # removing footnote markers leaves "Plan , the": close the gap
      text  = str_replace_all(text, "\\s+([,.;:)])", "\\1"),
      text  = str_squish(text),
      words = str_count(text, "\\S+")
    )
}

build_pool <- function(doc, file, first_page, last_page) {
  pdf_lines(file, first_page, last_page) |>
    lines_to_paragraphs() |>
    mutate(doc = doc, para_no = row_number())
}

# ---------------------------------------------------------------------------
# The pool
# ---------------------------------------------------------------------------

all_paras <- purrr::pmap(docs, build_pool) |> bind_rows()

# Section heading each paragraph sits under (kept for the record, not shown on
# the labelling sheet: the model never sees headings, so you should not either)
all_paras <- all_paras |>
  group_by(doc) |>
  mutate(section = ifelse(heading, text, NA_character_)) |>
  tidyr::fill(section, .direction = "down") |>
  ungroup()

pool <- all_paras |>
  filter(!heading, words >= MIN_WORDS) |>
  mutate(pid = sprintf("%s_%03d", doc, para_no)) |>
  group_by(doc) |>
  mutate(draw_order = sample(n())) |>        # the seeded random order
  ungroup() |>
  arrange(doc, draw_order) |>
  select(pid, doc, page, para_no, draw_order, words, section, text)

write_csv(pool, "data/pool.csv")

# ---------------------------------------------------------------------------
# The labelling sheet. Work down each document in draw_order until you have 15
# passages that pass the screen. Fill in the empty columns only. The text column
# is there to read; the analysis takes the text from pool.csv, by pid, so
# whatever your spreadsheet program does to quotation marks cannot change what
# was sent to the model.
# ---------------------------------------------------------------------------

sheet <- pool |>
  transmute(
    pid, doc, draw_order, page, words, text,
    include        = "",   # Y or N, by the written screening rule
    exclude_reason = "",   # if N: one short phrase
    label          = "",   # SECURITY, ECONOMIC or RIGHTS (if Y)
    confidence     = "",   # clear or ambiguous (if Y)
    rationale      = ""    # one line: the goal the passage is justified by
  )

if (!file.exists("data/labelling_sheet.csv")) {
  write_excel_csv(sheet, "data/labelling_sheet.csv")   # UTF-8 with BOM, so
                                                       # Excel opens it cleanly
} else {
  message("data/labelling_sheet.csv already exists: not overwritten.")
}

# ---------------------------------------------------------------------------
# Optional pilot pool from the AI Continent Action Plan, for trying the prompts
# before freezing them. Never part of the results.
# ---------------------------------------------------------------------------

if (file.exists("data-raw/COM_2025_165_pilot.pdf")) {
  pilot <- build_pool("PILOT", "data-raw/COM_2025_165_pilot.pdf", 2, NA) |>
    filter(!heading, words >= MIN_WORDS) |>
    mutate(pid = sprintf("PILOT_%03d", para_no), draw_order = sample(n())) |>
    arrange(draw_order) |>
    select(pid, doc, page, para_no, draw_order, words, text)
  write_csv(pilot, "data/pilot_pool.csv")
}

# ---------------------------------------------------------------------------
# What came out
# ---------------------------------------------------------------------------

cat("\nParagraphs found (after dropping footnotes):\n")
print(count(all_paras, doc))
cat("\nHeadings and units under", MIN_WORDS, "words, dropped:\n")
print(all_paras |> filter(heading | words < MIN_WORDS) |> count(doc))
cat("\nCandidate passages in the pool:\n")
print(pool |> group_by(doc) |>
        summarise(n = n(), median_words = median(words),
                  min_words = min(words), max_words = max(words)))
