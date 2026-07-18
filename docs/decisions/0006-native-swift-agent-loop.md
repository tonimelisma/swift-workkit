# ADR-0006 — The agent loop is a native Swift module on the ADR-0007 adapters

- **Status:** Accepted (Toni, 2026-07-18: "This is the way")
- **Date:** 2026-07-18
- **Deciders:** Toni

## Context

Increments 4–6 need an agent loop: send conversation + tool specs, stream the reply,
execute tool calls, feed results back, repeat. The constraints are the product's
spine: model neutrality (FR-001, NFR-001), full capability exposure (FR-060),
mid-task provider failover (FR-006), and Toni's direction — "I'd prefer a clean
native Swift module but need your research and input."

Increment 2 shipped two native streaming adapters covering all eleven curated
providers (ADR-0007). Live probes on 2026-07-18 verified tool calling works over
both wire formats, streaming and round-trip, and surfaced the decisive detail:
three providers require opaque per-message state (DeepSeek `reasoning_content`,
Google `thought_signature`, Anthropic signed thinking blocks) to be replayed on the
next request. Evidence: [research/agent-loop-runtimes.md](../research/agent-loop-runtimes.md).

## Decision

Build the loop as a **native Swift module in the monolith**, directly on the
ADR-0007 `ChatProvider` seam:

- A **neutral conversation model** (typed messages: text, reasoning, tool call,
  tool result) with a per-message **provider-extras bag** — opaque fields persisted
  and replayed verbatim to the provider that produced them, and stripped on
  provider switch (FR-006).
- **Adapter extensions**, not new adapters: tool-spec serialization and streaming
  tool-call delta accumulation in the two existing wire formats (index-keyed
  OpenAI-compatible, block-keyed Anthropic).
- A **turn state machine** with structured-concurrency cancellation, parallel tool
  execution, retry/backoff on 429/5xx, and a max-turns guard.
- Tool dispatch through the `Tool`/`ToolRunner` design in
  [plans/tool-architecture.md](../plans/tool-architecture.md).

No bundled runtimes, no subprocess, no third-party agent framework.

## Considered options

**Native Swift loop** *(chosen)* — Smallest delta from shipped code; total control
of the extras bag that FR-006/FR-060 demand; nothing new in the signed bundle.
Cost: we own retries, delta parsing, and provider drift — accepted for chat in
ADR-0007, and the loop inherits the same maintenance posture.

**Embedded TS/Python framework (Pydantic AI, LangGraph, Mastra, Vercel AI SDK) as a
subprocess** — Mature orchestration free. Rejected: bundles a Node/Python runtime
into a notarized hardened-runtime app; puts an IPC hop around every Swift tool
call; discards the shipped adapters; and still handles the provider-state quirks
unevenly. Structurally contradicts the native direction.

**LiteLLM / normalization proxy** — One wire format. Rejected: bundled Python plus
deliberate flattening of provider-specific fields — the opposite of FR-060, and it
breaks the extras round-trip the probes proved necessary. ADR-0007 rejected this
shape for chat; the reasons are stronger here.

**`open-agent-sdk-swift` (MIT)** — The one existing Swift-native agent SDK: full
in-process loop, MCP, session persistence. Rejected as a dependency: v0.10, ~26
stars, one maintainer, Claude-first design. Kept as a reference implementation —
it also proves the job is solo-sized in Swift.

**Apple Foundation Models provider protocol (WWDC26)** — Apple's own neutral
`LanguageModel`/`Transcript` abstraction; Anthropic and Google have announced Swift
packages. Rejected for now: macOS 27 minimum, vendor packages not yet shipped, and
eleven curated providers will not all appear on Apple's cadence. Watch; imitate its
`Transcript` typing; revisit when the curated vendors actually ship.

## Consequences

**Good.** The loop is continuous with everything shipped: same repo, same style,
same test approach (SSE fixtures + gated live smoke). The extras bag makes
reasoning state a first-class, persisted thing — which FR-063 (full traces) wanted
anyway. Failover (FR-006) becomes a defined transformation on one data structure.

**Bad.** We own more wire surface, and it drifts silently — quirk-class breakage
(a provider renaming a reasoning field) reaches users as a broken second turn, so
the live-smoke suite must cover a *two-request* tool round-trip per provider, not
just chat. Orchestration features frameworks give free (graphs, checkpointing,
eval hooks) are ours to build if ever needed.

**Bounded.** If adapter maintenance grows past what two wire formats justify, the
fallback is a normalization layer behind the same `ChatProvider` seam — the seam
this decision deliberately keeps.

**Extraction path (Toni, 2026-07-18: yes — "this is the way").** The loop is built
so it can later be carved into a Pydantic-AI-style SPM package ("AgentKit"): the
neutral conversation model + extras bag, the `ChatProvider` adapters, the
`Tool`/`ToolRunner` abstraction, the turn state machine with provider failover, and
the MCP client would move; the curated catalog, Keychain, trace store, built-in
tool policy, and all UI stay in the app, injected through protocols. The enforcing
discipline *now*, inside the monolith (ADR-0002 — no premature extraction): loop
and tool layers hold only neutral types and never import the app layer. Extraction
then is a mechanical move whenever it earns it. Boundary details:
[plans/tool-architecture.md](../plans/tool-architecture.md) §2.

## Validation

Tool calling verified live over both adapter formats before deciding (five
providers, streaming shapes captured, round-trips completed, quirks documented) —
see the research doc. The loop lands in increment 4; its DOD requires the
round-trip smoke against every funded provider.
