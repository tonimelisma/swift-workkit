# Work Agent — Roadmap

**Status:** Living. Last substantive change: 2026-07-16.

Order and deferrals only. What/why is in [PRODUCT.md](PRODUCT.md); testable statements
are in [REQUIREMENTS.md](REQUIREMENTS.md).

Increments are sized to the requirement, biased large — the DOR/DOD/spec overhead is
fixed, so amortize it. There are no dates. There is an order.

---

## The risk we're carrying

We decided to build the engine before choosing a real task. This is a known,
deliberate bet, and it has a specific failure mode: an engine with no target has
nothing to be right or wrong about. The previous draft of this project reached ten
phases and seven Swift packages without a single working feature, which is what this
looks like when it goes wrong.

**Mitigation:** increment 3 points the engine at one throwaway reference task. It is
not a feature and won't ship as one. It exists so "does the engine work" has an answer
that isn't a matter of opinion.

---

## Increment 1 — Documentation foundation ✅

Doc-only, straight to main.

This repo's specs, process, ADR format, and research system. Replaces the prior
`MACOS_FRONTEND_ROADMAP.md` draft, which was written without product input and is not
trusted.

## Increment 2 — Runtime and neutrality research → ADR-0005

Research spike. Produces docs and one ADR; no product code.

The question: **what runs the agent loop, given that model neutrality is
non-negotiable?** Neutrality eliminates the Claude Agent SDK and Claude Code outright —
both are single-vendor by construction. The live options:

- Custom Swift loop over provider-neutral HTTP.
- An embedded neutral framework (Pydantic AI, LangGraph, Mastra, Vercel AI SDK) as a
  bundled subprocess.
- A normalization layer (LiteLLM, or targeting the OpenAI-compatible endpoint that
  Ollama, vLLM, and most providers now expose).

Sub-question, same spike: what "neutral" means mechanically — adapter per provider vs
OpenAI-compatible vs proxy. FR-001 through FR-006 and NFR-001 are the constraints the
answer has to satisfy.

Real POCs against real providers, including one local model. Findings go to
`docs/research/`; the decision goes to ADR-0005.

**Done when:** ADR-0005 is written with alternatives and evidence, and a research doc
records what we measured so nobody redoes it.

## Increment 3 — Thin vertical slice

First code increment. Worktree, PR.

One task, end to end, in the monolith: real model call through the ADR-0005 runtime,
real local file read, real artifact out, real approval before a consequential action.
No packages, no XPC, no connections.

The reference task is a validation vehicle, not a product decision. Something like
*"read the documents in this folder and write me a summary file"* — mundane on purpose,
so any failure is the engine's fault and not the task's.

**Done when:** the slice runs against at least two providers, one of them local
(FR-002, FR-003), and the requirements it implements are traced and tested.

## Increment 4 — Second provider, cold

Prove FR-001 and NFR-001 are real by adding a provider we didn't design against. If it
touches anything outside its adapter and registration, NFR-001 is false and we find out
now rather than after ten features have leaked provider assumptions.

**Done when:** a provider is added without changes outside its adapter — or NFR-001 is
rewritten to say what's actually true.

---

## Deferred, with the reason

| Deferred | Until |
|---|---|
| **The real first task** | The engine exists. Then we pick one from actual work Toni does, not from a category list. |
| **Minimum macOS version** | The first increment that wants an API we'd have to gate. Currently nothing does. |
| **Background execution** (LaunchAgent, XPC) | The product is validated. Retrofit cost is real and acknowledged; paying it before we know the product is worse. |
| **SPM package extraction** | We know where the seams are. (ADR-0002) |
| **Connections** (Gmail, Drive, M365) | A real task needs one. |
| **Native app control** (Accessibility, screen capture) | Structured APIs demonstrably fall short. ADR-0003 keeps this possible. |
| **Sandboxed code execution** | Something needs to run generated code. NFR-004 holds the line meanwhile. |
| **Automations, scheduling** | Post-engine. |
| **Onboarding, multi-user, enterprise policy** | Distribution reaches people who aren't Toni. |
