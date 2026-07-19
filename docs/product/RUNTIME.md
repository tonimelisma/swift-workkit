# The agent runtime — product north star

**Status:** Living north star, created 2026-07-18 at Toni's direction ("let's do a
comprehensive doc increment so this discussion will be stored as the north star for
the project"). This is the *second product* in this repo: the native Swift
agent-runtime SPM package that [PRODUCT.md](PRODUCT.md)'s app is built on. Toni:
*"Work Agent will be the reference app implementation building on top of the SPM
which we carve out."*

What it must do for increment 4 specifically is in
[plans/agent-loop-implementation.md](../plans/agent-loop-implementation.md); the
developer-facing API shape is in [plans/runtime-api.md](../plans/runtime-api.md);
the evidence is in the research docs linked throughout. This doc is the durable
*why and what* — the two most load-bearing sources are
[research/agent-framework-comparison.md](../research/agent-framework-comparison.md)
and [research/apple-llm-stack-second-opinion.md](../research/apple-llm-stack-second-opinion.md).

---

## 1. The thesis

The Swift LLM stack split into two layers in mid-2026, and they are filling at
opposite speeds:

- **The model layer is commoditizing in weeks.** Apple shipped a neutral
  provider protocol (`LanguageModel`/`LanguageModelExecutor`) in the OS 27
  Foundation Models framework; Anthropic and Google shipped v0.1 provider
  packages; Hugging Face cloned the entire API surface for older OSes
  (`AnyLanguageModel`, nine backends). The FM API shape is winning as the Swift
  ecosystem's lingua franca.
- **The work layer above it is empty.** Durable execution, restart-surviving
  interrupts and approvals, run policy and limits, retries and provider
  failover, context assembly, MCP, tool instrumentation, traces, replay, and
  evals — the capabilities that make Python/TS developers adopt
  LangGraph/LangSmith, Pydantic AI, and the OpenAI Agents SDK — exist nowhere
  in Swift, and Apple ships none of them (verified against the macOS 27 SDK:
  not even an evaluations API).

The runtime is the bet on that empty layer: **Apple supplies intelligence
sessions; we supply durable work.** It is the same "durable value is at the app
layer" conviction as PRODUCT.md §1, applied one level down — and it inherits the
same neutrality spine: any conforming model, no vendor welding, provider-exclusive
capabilities exposed rather than flattened.

Two capabilities are weak *even in Python/TS* and are therefore the sharpest
claims: **side-effect safety** (idempotency classification, indeterminate-outcome
recovery — every framework hand-waves it) and **cross-provider mid-task
failover** (nobody has it; it falls out of our transcript-archive design).

## 2. Who it's for

Swift developers building Mac and iPhone apps with LLM features — the audience
Apple just handed a model protocol and nothing to run serious work on. They are
*not* Work Agent's end users; this product's "user" writes Swift. Work Agent is
its reference implementation and first proof.

## 3. What it is

A native Swift SPM package (iOS 27 + macOS 27) sitting between an app and
Foundation Models:

- **Durable runs**: append-only run journal, versioned transcript archive,
  checkpoints, crash-safe resume; the run — not the process — is the unit of work.
- **Interrupts that survive restart**: questions, approvals, and pauses as
  serializable state, not live continuations.
- **Run policy**: composable limits (turns, tokens, cost, time, tool calls),
  typed retry/backoff, model fallback, cross-provider failover.
- **Tool instrumentation without a second tool type**: any
  `FoundationModels.Tool` gains tracing, budgets, timeouts, and corrective
  error handling by being run through the runtime; effects/idempotency arrive
  as data (annotations), not as a competing protocol.
- **Provider executors as batteries**: OpenAI-compatible and Anthropic
  executors with full-fidelity provider state (reasoning round-trips, thought
  signatures) — plus acceptance of *any* injected `LanguageModel`, vendor
  packages included.
- **A public conformance suite**: scripted-model semantics tests any provider
  package can be certified against — the ecosystem hook.
- **Local-first observability**: full-fidelity traces, deterministic replay,
  eval helpers; test doubles (scripted models, virtual clocks, fixture
  recorders) as first-class public API.
- **MCP**, behind an explicit schema-degradation ladder rather than silent
  flattening.

## 4. What it is not

- Not a model SDK or a second session API — Apple owns the intelligence nouns
  (`LanguageModel`, `Transcript`, `Tool`, `Generable`); we never ship lookalikes.
- Not "LangChain for Swift" — no feature-checklist chasing, no graph DSL until a
  real need, no RAG/vector/memory stack by default.
- Not a cloud product — no control plane, no required account; LangSmith-class
  *hosted* monitoring is explicitly out (a local-first studio is a possible
  later product, see §6).
- Not multi-agent-first — teams/handoffs wait for evidence a single durable
  agent is insufficient.

## 5. Relationship to Work Agent

Work Agent (PRODUCT.md) stays a macOS product for non-developers; the runtime is
the layer it proves. The dependency is one-way — the package never knows the app
— and the boundary is enforced now inside the monolith and extracted per
ADR-0002/ADR-0006. Work Agent keeps its own executors for all eleven curated
providers (consistency, BYOK credentials, failover fidelity) even where vendor
packages exist; vendor packages are conformance references and user-selectable
alternatives, not foundations. Sometimes provider capabilities exceed the FM
protocol — Toni: "for Claude and Gemini their FM API doesn't cover all their
functionality. so sometimes we'll need to go direct to the API" — so the runtime
keeps two escape hatches: provider-native options on executor configuration, and
a separate direct-API surface for non-conversational endpoints (batches, file
stores) that don't belong in a transcript.

## 6. Open questions

Decided by Toni when they block something, not before:

- **Name.** "AgentKit" is a working label only; the public name is unchosen.
- **License and openness.** Open source, source-available, or private — undecided,
  and it shapes the conformance-suite ecosystem play.
- **Repo home and split timing.** Lives in this repo until extraction earns a
  separate one.
- **iOS scope.** "Runs on iOS" (compile + conformance) vs suspension-safe durable
  runs (BGTaskScheduler-aware) — the second is the differentiator and the cost.
- **The studio.** A local-first trace/replay/eval app (Work Agent's trace UI,
  generalized) is a candidate third product, unscheduled.
- **Release gate.** No public tag before the OS 27 GA — beta ABI churn is real
  (observed once already).
