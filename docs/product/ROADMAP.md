# AgentKit — Roadmap

**Future only.** What exists is in [PRODUCT.md](PRODUCT.md) and
[ENGINEERING.md](../engineering/ENGINEERING.md); a shipped item is deleted from this
list. Items are in priority order, laser-focused on the MVP: **everything is judged
by how the Work Agent app uses it** (Toni, 2026-07-19: "a sprawling SPM is unwieldy
and will never be adopted, we need laser focus and ruthless prioritization for the
MVP"). A planning agent takes items from the top and produces [plans/](../plans/);
nothing is picked from anywhere else. App-side backlog:
[../app/APP.md](../app/APP.md).

**The vision:** Apple gave every Swift app a language-model session with three
sockets — model, tools, profile — and left the sockets empty. This package fills
them with ready parts: executors for the clouds that ship no FM provider, native
tools a work assistant actually needs, a recorder that remembers what a session
forgets, MCP for the rest of the world, test doubles that make agent code testable.
**Attach, don't adopt** — nothing wraps or replaces Apple's API. Apple's own
on-device models are supported too — "Apple Foundation Models support is cheap
since it's built-in" — but no third-party local models, ever. Model-neutral,
local-first, with the Work Agent app as the proving ground; SPM-as-product work
waits in the riffraff until the app is polished and demand is real.

**The completeness rule:** every capability the README promises is either in
PRODUCT.md (built) or on this list (the MVP items or the riffraff). A promise in
neither place is a bug.

**Provider status (2026-07-19):** all eleven providers funded and keyed, including
xAI, Meta, and Thinking Machines (previously never exercised), plus the Brave
Search API key. Nothing below is blocked on quota or keys anymore; GLM alone needs
code (JWT auth), not money.

---

## 1. The attachment refactor — reshape the package to the pivot

The 2026-07-18/19 re-visioning decided the architecture; nothing has refactored the
code to match, and Toni caught the gap ("we made quite a re-visioning of the whole
SPM and I don't see that refactoring anywhere on the roadmap"). This item makes the
tree match [plans/runtime-api.md](../plans/runtime-api.md):

- **The Recorder is born**: the journal becomes the Recorder's store;
  `InstrumentedTool` becomes `recorder.instrument(_:)`; profile hooks capture
  prompts/responses/usage; timestamps, full untruncated tool output, and tool
  failures recorded.
- **The engine dissolves**: `TaskCoordinator` and `RunPolicy` leave the package and
  become Work Agent app code (the conductor is the app's); no session-owning public
  API remains. Deleting from the SPM the stuff we won't do.
- **Utilities extracted**: `TranscriptArchive.save/load` + `replay(to:)` (the
  provider-state strip) as small free functions; the checkpoint store stays as the
  plain persistence helper it already is.
- Tests migrate with the code; the suite stays green on both platforms.

**Before the carve-out, deliberately**: the app absorbs its conductor while both
still live in one repo.

## 2. Carve the app out; make this an SPM-root repo

Execute [plans/app-carveout.md](../plans/app-carveout.md): the app moves to its own
repo, `Package.swift` moves to the repo root, CI becomes `swift test` on both
platforms. Blocked only on the destination repo existing.

## 3. Verify the core, close the gaps

Everything here is unblocked now that all keys and quota exist:

- **Live-verify all eleven providers** — first-ever runs for xAI, Meta, and
  Thinking Machines; re-verify OpenAI and MiniMax now funded; one full tool-cycle
  smoke per provider, not just streaming.
- **`web_search` live** with the supplied Brave key (FR-083).
- **Human verification of send → quit → resume** — the app's core loop, never yet
  watched working end to end.
- **Wire `ask_user` and `update_plan`** into the app (question card, plan display) —
  built tools delivering zero value until surfaced.
- **Apple on-device model, verified**: a gated `SystemLanguageModel` test on an
  eligible device — cheap, built-in, decided in ("we'll do that").
- **GLM JWT auth** — last and least: one exotic model, a third auth style.

## 4. Cost display — the Recorder's first user-facing slice

BYO-key users watch their spend. The Recorder's usage/cost accounting surfaced in
the app as "this conversation cost $0.42." Small, genuinely wanted, and the first
thing that *reads* the Recorder's store — which keeps item 1 honest.

## 5. Email: Gmail and Outlook via MCP

"Gmail and Outlook via MCP. No one uses the local mail app. Put them ASAP." The
assistant's killer capability, and it carries the MCP foundation with it: the
client behind a package trait, the schema degradation ladder (`GenerationSchema`
accepts a strict JSON Schema subset; unsupported keywords reported with path and
fallback, never silently flattened), Gmail and Outlook servers as the proving
integrations — real-world schema corpora, OAuth handled by the servers, not by us.
The journal-before-execute guard in `recorder.instrument` starts earning rent
here: "may have sent" is asked about, never silently repeated.

## 6. Document creation: PDF, docx, xlsx, pptx — and Google via MCP

"Yes all office doc creation too ASAP. Google via MCP if available. Docx xlsx pptx
locally." `ToolKitDocuments`: PDF via PDFKit; docx/xlsx/pptx created natively (all
three are OOXML zips — the ZIPFoundation path that reads docx writes them); no
code-execution sandbox in the loop, unlike every competitor. Google
Docs/Sheets/Slides only through existing MCP servers riding item 5 — we never
build our own Google OAuth. Per-format specs (templates, styling scope,
append-vs-create) researched at planning; xlsx/pptx *reading* settled in the same
plan.

## 7. ToolKitPIM: Contacts, Calendar, Reminders

"What's on my calendar" — the local-first answer to Cowork's OAuth connectors:
EventKit/Contacts frameworks, no sign-in, works offline. Cross-platform domain
target owning the schemas; TCC usage-description obligations documented per tool;
per-tool specs researched at planning. (App control stays dead: "There's MCPs for
that.")

---

## Riffraff — parked, each with its revival trigger

Not scheduled, not deleted. Nothing here gets built until its trigger fires.

| Parked | Revival trigger |
|---|---|
| **Recorder completion**: output budgets + spill-to-store, the `read_tool_output` history tool, compaction-made-safe-by-recall | Real chats hitting the context window (per-tool paging in `read_file`/`fetch_url` carries the MVP until then) |
| **Replay + evals**: recordings replayed against other models/prompts, trajectory diffing, recorded-case CI suites | We need regression coverage when swapping models — or a developer asks |
| **Provider fidelity tiers**: neutral prompt-caching API first, then hosted-search/thinking-budget neutral APIs, direct batch/file-store clients | Item 4's cost data shows caching pays; a real feature needs the rest |
| **Cross-provider eval matrix** (generated conformance table) | SPM-as-product marketing matters; item 3's per-provider smokes carry the MVP |
| **API hardening**: DocC, `Examples/`, public conformance kit | A developer other than us asks how to use or certify against the package |
| **Publication**: name decision, README re-audit, first public tag | OS 27 GA **and** the app polished **and** demand signals |
| **iOS**: `ToolKitForiOS`, security-scoped file bodies, suspension validation | The macOS app is polished first; the suspension-safe checkpoint design is already done and costs nothing to keep |
| **The studio** (local trace/replay/eval app) | PM-grade inspection demand in real use; needs Recorder completion |
| **Composable run limits, restart-surviving interrupts, side-effect enforcement machinery** | Real use proves them ("the functionality and plans here got ahead of where I wanted to go") |
| **Shell / code execution tool** | An isolation design exists; native document creation removed its main justification |
| **Graph DSL, multi-agent, RAG/memory stack** | Non-goals until a real consumer proves need |
| **Package/repo split** | Release cadences demonstrably diverge |
| **Third-party local models** | Never ("we will not build third party local models"). Apple's built-in models are supported; that is the line. |
