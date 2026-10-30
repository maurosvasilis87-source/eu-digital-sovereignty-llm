# Codebook: Framings of EU Digital Sovereignty

Version 1, 27/10/2026. Written before screening or labeling any passage.

## Unit
One passage: a body paragraph from JOIN(2025) 140 or COM(2026) 503, 
as extracted by R/01_build_pool.R. I code the passage text only, 
not the section heading it sits under, because the model sees only the passage.

## 1. Screening rule
Include (YES) if the passage states or clearly implies a goal that an
EU action serves, i.e. why the EU should do something.
Exclude (NO) if it only describes facts, lists instruments, partners,
events or initiatives, or announces an action without saying what it is for.
A passage that diagnoses a problem without proposing a response is excluded.
Difficulty in choosing a frame is never a reason to exclude.

## 2. Categories
Code the main justification for EU action, not every theme mentioned.

- SECURITY: strategic autonomy, cyber-security, resilience, reducing
  external dependence, protection against threats or coercion.
- ECONOMIC: competitiveness, innovation, industrial capacity,
  investment, growth.
- RIGHTS: fundamental rights, democratic accountability, privacy and
  data protection, public control over digital technologies.

## 3. Tie-break rule
- Dependence on non-EU suppliers, supply chains, 'economic security': ECONOMIC
- EU values, 'trustworthy' or 'human-centric' technology: RIGHTS
- Several goals listed with equal weight: code the goal the proposed
  action most directly serves. If no specific action is named, code the
  goal the passage develops most, and mark the passage ambiguous.

## 4. Confidence
- clear: one frame is plainly the justification; I chose it without
  the tie-break rule or a second reading.
- ambiguous: frames compete or the justification is only implied;
  I needed the tie-break rule, a second reading, or changed my mind.

For every ambiguous passage, the rationale names the runner-up frame.

## 5. Procedure
I work down each document in draw_order without skipping and stop at
the 15th included passage. Every exclusion gets a reason. Labels and
confidence are set before any model call and not revised after I see
the model's answers.