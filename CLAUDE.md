# Work Agent — Working Agreement

Native macOS app: an AI agent that does real work on the user's Mac, for people who
are not developers and not power users.

**The thesis:** every competing agent is welded to one vendor's model. We bet inference
commoditizes and the durable value is at the app layer. Model neutrality is not a
feature of this product — it is the reason it exists. Any decision that quietly
couples us to one provider is wrong by default.

---

## The docs

Read the ones your increment touches. Do not read all of them by reflex.

| Doc | Answers | Rule |
|---|---|---|
| [docs/product/PRODUCT.md](docs/product/PRODUCT.md) | What are we building, for whom, why, and what are we *not* building | Changes when the product bet changes |
| [docs/product/REQUIREMENTS.md](docs/product/REQUIREMENTS.md) | What must be true, testably, with IDs | Changes every increment that adds or alters behavior |
| [docs/product/ROADMAP.md](docs/product/ROADMAP.md) | What order, and what's deliberately deferred | Changes when sequencing changes |
| [docs/engineering/ENGINEERING.md](docs/engineering/ENGINEERING.md) | How the system is built *right now* | Always reflects reality — never aspiration |
| [docs/decisions/](docs/decisions/) | Why we chose this over the alternatives, at a point in time | Append-only; supersede, never rewrite |
| [docs/research/](docs/research/) | What we learned from outside this repo | Living — update in place, don't append journal entries |

**ENGINEERING.md vs ADRs** is the distinction people get wrong. An ADR is a decision
frozen at a moment, with the alternatives and the reasoning intact. ENGINEERING.md is
the current synthesis. When an ADR is superseded, the old ADR stays exactly as written
and ENGINEERING.md moves on.

These docs are MECE. If a fact belongs in two of them, it belongs in one and is linked
from the other. Duplicated facts drift and then lie.

---

## Non-negotiables

1. **Specs are the source of truth, and they lose to you.** If a requirement or ADR
   contradicts what Toni just asked for, that is not a blocker and not an argument.
   Surface it as a clarification — "this contradicts FR-014 / ADR-0003, are we changing
   that decision?" — and if the answer is yes, update the spec *in the same increment*.
   Never leave code and spec disagreeing. Never use a spec to refuse a request.

2. **Every behavior change updates the requirements.** No exceptions, including for
   changes that feel too small to document. A requirement that describes last month's
   behavior is worse than no requirement.

3. **Requirements have IDs and code points back.** See Traceability below.

4. **Research gets written down without being asked.** Any external lookup or POC that
   took real work — API availability, performance measurements, whether a framework can
   actually do the thing — produces or updates a doc in `docs/research/`. The test is:
   *would we have to redo this work to know it again?* If yes, write it. Trivial lookups
   stay in the transcript.

5. **Prefer larger increments.** The process below has fixed overhead. Amortize it. An
   increment should be a meaningful, deliverable slice — not a chore.

---

## Traceability

Requirements use flat, prefixed, permanent IDs: `FR-001` (functional), `NFR-001`
(non-functional). **IDs are never reused and never renumbered.** A dropped requirement
is marked `Superseded` or `Removed` in place, keeping its number forever. Renumbering
breaks every reference in the codebase, which is the whole failure mode we're avoiding.

In code, at the point where the requirement is actually satisfied:

```swift
// REQ: FR-012 — provider adapters are selected at runtime, never compiled in.
```

In tests, the ID goes in the display name so it's greppable with zero ceremony:

```swift
@Test("FR-012: selecting a provider does not require a rebuild")
func providerSelectionIsRuntime() async throws { ... }
```

We deliberately do **not** declare a Swift Testing `@Tag` per requirement. Tags would
give us `--filter` by requirement, but cost a tag declaration per ID forever. If we
later want filtering badly enough to pay that, an ADR revisits it.

Grep is the traceability tool: `rg "FR-012"` finds the requirement, the code, and the
tests. If it finds only the requirement, the requirement is unimplemented — that is a
signal, not a bug in the scheme.

---

## Increment workflow

An increment is one unit of deliverable work. **Code increments** use a worktree and a
PR. **Doc-only increments** commit straight to main — no worktree, no PR — since they
can't break anyone else's build.

### Before starting: Definition of Ready

Post this list with ✅/❌ per item. Any ❌ means we align before writing code.

- ✅/❌ The requirement is clear, and we know which FR/NFR IDs are in play (new or existing)
- ✅/❌ We know which specs change: requirements, ENGINEERING.md, which ADRs
- ✅/❌ Any decision with real alternatives has an ADR planned, not an assumption
- ✅/❌ We have read the affected code paths and can say concretely how they change
- ✅/❌ Research needed to make this decision is done, or is explicitly this increment's first step
- ✅/❌ Toni has agreed to the scope

Don't fake a ✅. A ❌ with a sentence about why is the point of the list.

### During

```bash
git worktree add ../wa-<slug> -b <slug>    # code increments only
```

Work in the worktree. Doc-only increments that won't collide with another agent skip
this entirely and commit to main.

### Before finishing: Definition of Done

Post this list with ✅/❌ per item. A ❌ needs a sentence saying why it's acceptable —
or it isn't done.

- ✅/❌ The deliverable works, and I verified it by running it — not by inferring from tests
- ✅/❌ Tests written for the new requirement IDs, and the full suite is green (paste the result)
- ✅/❌ Requirements updated: new IDs added, changed IDs edited, dead IDs marked superseded
- ✅/❌ ENGINEERING.md reflects reality after this change
- ✅/❌ ADRs written for decisions made; superseded ADRs marked, not rewritten
- ✅/❌ Research docs written or updated for anything learned the hard way
- ✅/❌ CLAUDE.md updated if the process itself changed
- ✅/❌ Code references its requirement IDs

Then:

```bash
gh pr create ...          # code increments
# squash merge, delete branch
git worktree remove ../wa-<slug>
git branch -d <slug>
```

Report the DOD list honestly. A red ❌ that's explained is useful. A green ✅ that's
wrong destroys the value of every other line.

---

## Conventions

- Swift, SwiftUI, `swift-testing`. Monolith for now — SPM packages get extracted when
  we know where the seams are, not before. See ADR-0002.
- Distribution is Developer ID + notarized, never Mac App Store. The sandbox would
  forbid most of what this product does. See ADR-0003.
- Never present MCP, tool schemas, JSON-RPC, OAuth scopes, or AXUIElement to the user.
  They are implementation. Users see work, sources, actions, and approvals.

`AGENTS.md` is a symlink to this file.
