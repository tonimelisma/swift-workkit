# Work Agent — Roadmap

**Status:** Living. Last substantive change: 2026-07-16.

Order and deferrals only. What/why is in [PRODUCT.md](PRODUCT.md); testable statements
are in [REQUIREMENTS.md](REQUIREMENTS.md).

Increments are sized to the requirement, biased large — the DOR/DOD/spec overhead is
fixed, so amortize it. There are no dates. There is an order.

---

## Sequencing: engine first, then tasks

Tasks get picked once we have **a working app that talks to an LLM and a set of tools
we've actually tested.** Not before.

The reasoning: choosing tasks up front means choosing them from imagination. Choosing
them after the engine and tools exist means choosing from what the thing demonstrably
does — which is a fundamentally better-informed decision, and cheap, because by then
we'll know the real cost of each candidate.

The failure mode this carries is real and worth naming: an engine with nothing to be
right or wrong about grows forever. The previous draft of this project reached ten
phases and seven Swift packages without one working feature. What keeps us out of that
hole is that increments 3–5 each have a concrete, falsifiable exit — a real model call,
a real tool doing a real thing, a second provider working cold. None of those are
opinions. Increment 6 is a hard stop where we pick tasks or admit the engine isn't
done.

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

## Increment 3 — A working app that talks to an LLM

First code increment. Worktree, PR.

The agent loop from ADR-0005, running in the monolith, against one real provider. A
durable task the user can create and watch. No tools yet, no packages, no XPC, no
connections.

**Done when:** a real model call happens, its result lands in a task that survives an
app restart (FR-010, FR-011), and the task's status is observable while it runs
(FR-012).

## Increment 4 — First tools, tested

Tools the engine can actually call, exercised individually until we trust them. Scope
of the starter set is an open question below.

This increment is where approval lands too — the first tool with a consequential effect
forces FR-020 through FR-025 to become real rather than specified.

**Done when:** each tool has tests proving it does what it claims, and a tool with a
consequential effect cannot run without approval.

## Increment 5 — Second provider, cold: the real neutrality test

Add a provider we did not design against, and make the increment-4 tools work through
it unchanged.

**This is positioned after tools deliberately.** Tool calling is where provider
neutrality actually bites — Anthropic emits `tool_use` blocks, OpenAI emits
`tool_calls`, Ollama varies by model, and some open models approximate it with JSON
mode. Testing neutrality over plain-text conversation would prove almost nothing and
would let us believe FR-001 was satisfied months before it was.

**Done when:** the provider is added without changes outside its adapter and its
registration, and every increment-4 tool works through it — or NFR-001 gets rewritten
to say what's actually true. Both outcomes are acceptable. Quietly keeping a false
NFR-001 is not.

## Increment 6 — Pick the tasks

Not a build increment. A product decision, made with the engine and tools in front of
us, drawn from work Toni actually does — not from a category list.

**Done when:** the real first task is named in PRODUCT.md and its requirements are
written.

---

## Deferred, with the reason

| Deferred | Until |
|---|---|
| **The real first task** | Increment 6 — once a working app talks to an LLM and has tools we've tested. Picked from actual work Toni does. |
| **Which tools to build first** | Increment 4's scope. Open — see below. |
| **Minimum macOS version** | The first increment that wants an API we'd have to gate. Currently nothing does. |
| **Background execution** (LaunchAgent, XPC) | The product is validated. Retrofit cost is real and acknowledged; paying it before we know the product is worse. |
| **SPM package extraction** | We know where the seams are. (ADR-0002) |
| **Connections** (Gmail, Drive, M365) | A real task needs one. |
| **Native app control** (Accessibility, screen capture) | Structured APIs demonstrably fall short. ADR-0003 keeps this possible. |
| **Sandboxed code execution** | Something needs to run generated code. NFR-004 holds the line meanwhile. |
| **Automations, scheduling** | Post-engine. |
| **Onboarding, multi-user, enterprise policy** | Distribution reaches people who aren't Toni. |

---

## Open: the increment-4 starter tool set

Needs answering before increment 4, not before increment 2 or 3.

The tools we pick determine which tasks are available to choose from in increment 6, so
this is a smaller version of the same decision — it constrains the product while
looking like an engineering choice. Worth deciding deliberately.

The obvious candidates, roughly in order of cost:

- **Local files** — read, search, write within user-approved folders. Cheapest, no
  OAuth, no network, and exercises approval (writing) and sources (reading). Almost
  certainly in the set.
- **Shell / subprocess** — powerful and general, but NFR-004 forbids arbitrary host
  execution, so this needs an isolation story first. Probably not in the starter set.
- **A connected service** (Gmail, Drive) — the most representative of real work, and by
  far the most expensive: OAuth, token refresh, revocation, API surface. Likely too
  much for increment 4.
- **Native app control** — deferred; ADR-0003 keeps it possible.

Not decided. Local files is the likely floor; the question is whether anything joins it.
