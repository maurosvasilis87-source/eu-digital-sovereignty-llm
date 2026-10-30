# The schema. Identical in every run, so the only thing that varies between
# Prompt A and Prompt B is the instruction. The descriptions are sent to the
# model, so they are prompt text: keep them neutral and leave them alone.
type_frame <- type_object(
  "The dominant framing of a passage from an EU policy document.",
  frame = type_enum(
    c("SECURITY", "ECONOMIC", "RIGHTS"),
    "Exactly one of SECURITY, ECONOMIC or RIGHTS."
  )
)

# ---------------------------------------------------------------------------
# Prompt A: the prompt as written
# ---------------------------------------------------------------------------

prompt_a <- "
You are coding passages from European Union policy documents on digital and
technology policy for a political science project.

Classify the dominant political framing of each passage: the main goal the
passage uses to justify EU action. Choose exactly one category.

SECURITY: strategic autonomy, cybersecurity, resilience, reducing external
dependence, protection against threats or coercion.
ECONOMIC: competitiveness, innovation, industrial capacity, investment,
growth.
RIGHTS: fundamental rights, democratic accountability, privacy and data
protection, public control over digital technologies.

Choose the category of the main justification, not every theme the passage
mentions.

Tie-break rule
- Dependence on non-EU suppliers, supply chains, 'economic security': ECONOMIC
- EU values, 'trustworthy' or 'human-centric' technology: RIGHTS
- Several goals listed with equal weight: code the goal the proposed
  action most directly serves. If no specific action is named, code the
  goal the passage develops most, and mark the passage ambiguous.
"

# ---------------------------------------------------------------------------
# Prompt B: the same task, reworded. A reasonable alternative phrasing, not a
# worse one: the question is whether two defensible wordings disagree.
# ---------------------------------------------------------------------------

prompt_b <- "
Below is a passage from an EU policy document about digital technology. Ask
yourself why, according to the passage, the EU should act, and answer with
the one category that best matches that reason.

SECURITY means the reason is to protect the EU: its autonomy, its resilience,
its cybersecurity, or its independence from outside suppliers and from threats
or coercion.
ECONOMIC means the reason is prosperity: competitiveness, innovation,
industrial capacity, investment or growth.
RIGHTS means the reason is to protect people and democracy: fundamental
rights, democratic accountability, privacy and data protection, or public
control over digital technologies.

If more than one reason appears, choose the one the passage relies on most.

Tie-break rule
- Dependence on non-EU suppliers, supply chains, 'economic security': ECONOMIC
- EU values, 'trustworthy' or 'human-centric' technology: RIGHTS
- Several goals listed with equal weight: code the goal the proposed
  action most directly serves. If no specific action is named, code the
  goal the passage develops most, and mark the passage ambiguous.
"
