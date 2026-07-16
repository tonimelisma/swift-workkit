# ADR-0001 — Record architecture decisions, in this format

- **Status:** Accepted
- **Date:** 2026-07-16
- **Deciders:** Toni
- **Supersedes:** —
- **Superseded by:** —

## Context

Decisions on this project get made in conversation, mostly with agents, and then
evaporate. Six weeks later nobody — human or agent — remembers whether a choice was
reasoned or accidental. The reliable symptom is an agent "fixing" a deliberate decision
because the reasoning wasn't written down, or relitigating a settled question because
the alternatives weren't recorded.

The previous roadmap draft demonstrated the failure precisely: it asserted a custom
Swift agent loop, seven packages, and XPC as though they were facts rather than choices,
with no alternatives and no reasoning. Unreviewable, because there was nothing to
disagree with.

We also need a home for decisions that is *not* the engineering doc. Those two things
have opposite lifecycles: current-state synthesis changes constantly, a decision record
must not change at all.

## Decision

Record architecturally significant decisions as numbered Markdown files in
`docs/decisions/`, named `NNNN-kebab-title.md`, using the format of this file — a
lightly trimmed [MADR](https://adr.github.io/madr/).

**Significant** means: expensive to reverse, constrains later decisions, or a reader
would reasonably ask "why on earth is it like this?" Library picks and naming
conventions are not ADRs. If it's arguable and durable, it's an ADR.

**Append-only.** An ADR is a decision frozen at a moment. When it stops being true,
write a new ADR and mark the old one `Superseded by ADR-NNNN`. Never edit the reasoning
of an accepted ADR — the wrong turns are the value. A record of what we believed is
worthless once it's been quietly corrected.

**Considered options carry their tradeoffs.** An ADR listing alternatives without saying
what was bad about the winner and good about the losers hasn't recorded a decision, it
has recorded a preference. The rejected options are why the file exists.

The sections: Context, Decision, Considered options (with tradeoffs), Consequences
(including bad ones), and — where it exists — Validation.

## Considered options

**MADR, trimmed** *(chosen)* — Widely used, Markdown, keeps tradeoff analysis as a
first-class section. Costs some ceremony per decision, and the full template has
sections we'd leave empty.

**Nygard's original ADR format** — Lighter: context, decision, consequences. Genuinely
less friction. Rejected because it has no dedicated place for considered options, which
is the section that stops a future agent from redoing the analysis. That's the section
we most need.

**Decisions inside ENGINEERING.md** — One less file to find. Rejected: opposite
lifecycles. ENGINEERING.md must be edited freely to stay true; ADRs must not be edited
at all. Merging them means one of those properties dies, and it would be the ADR one.

**No ADRs; rely on git history and PRs** — Zero overhead. Rejected: commit messages
record *what* changed, and PR threads are unsearchable, unindexed, and lost if the repo
moves. Neither survives an agent's context window, which is the actual reader here.

## Consequences

**Good.** Decisions become reviewable and refusable. A superseded ADR shows the reasoning
that changed, which is often more useful than the current answer. Agents can read why
and stop reflexively fixing intent.

**Bad.** Overhead per decision, and it lands hardest exactly when momentum is highest.
The predictable failure is ADRs written after the fact to satisfy the DOD — fiction with
a number on it. The DOR asks which ADRs an increment will need *before* work starts,
specifically to catch this.

**Also bad.** "Architecturally significant" is a judgment call and will be applied
inconsistently. Better than the alternatives, which are ADRs for everything (noise) or
for nothing (amnesia).
