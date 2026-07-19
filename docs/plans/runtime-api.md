# Plan: the runtime's developer-facing API — future state

**Status: north star, 2026-07-18.** The API shape the runtime SPM is aiming for,
recorded from the 2026-07-18 design discussion at Toni's direction. Product
rationale: [../product/RUNTIME.md](../product/RUNTIME.md). Increment-4 internals:
[agent-loop-implementation.md](agent-loop-implementation.md). Like every plan,
binding details are confirmed at each increment's DOR; unlike increment plans, this
doc describes the *end state* several increments converge on.

---

## 1. The one rule: every noun has exactly one owner

Mishmash happens when two frameworks own the same noun and developers convert
between them. The runtime forbids it structurally: **Apple owns the intelligence
vocabulary, the runtime owns the work vocabulary**, and no Apple type is wrapped in
a lookalike. The full ownership map:

| Capability | Developer writes | Owner |
|---|---|---|
| Pick a model | any `LanguageModel` — vendor package, ours, `SystemLanguageModel` | Apple protocol |
| Structured output / tool args | `@Generable`, `GenerationSchema` | Apple |
| Prompts, instructions | `Prompt`, `Instructions` | Apple |
| Conversation content | `Transcript` entries | Apple (we store, never translate) |
| One-shot call | `session.respond(to:)` | Apple — untouched, never shadowed |
| Define a tool | `FoundationModels.Tool` | Apple (see §3) |
| Run durable work | `runtime.run(...)` / `runtime.resume(...)` | **Runtime — the one replaced entry point** |
| Observe a run | `run.events` (`AsyncSequence`) | Runtime |
| Limits, retry, failover | `RunPolicy` | Runtime |
| Interrupts, approvals, checkpoints | `Interrupt` + resume APIs | Runtime |
| Traces, replay, evals, test doubles | journal readers, scripted models, virtual clocks | Runtime |
| MCP | runtime MCP client | Runtime |
| Provider-exclusive features | executor configuration; separate direct client for non-conversational APIs | Runtime, additive |

The seam is one teachable sentence: *`respond()` for a quick answer, `run()` for
work that must survive.*

## 2. The canonical usage example

The hello-world and the advanced path use the same runtime — progressive
disclosure is never a second, less observable engine:

```swift
import FoundationModels
import <RuntimeName>            // no type shadows either import

@Generable struct ReportArgs { var folder: String }

struct WriteReport: Tool {                        // pure Apple, from any tutorial
    let description = "Write the weekly report"
    func call(arguments: ReportArgs) async throws -> String { ... }
}

let model = ClaudeLanguageModel(name: .sonnet5, auth: .apiKey(key))   // vendor package
// or: OpenAICompatibleModel(.deepSeek, apiKey: key)                  // our executor, same slot

let run = try await runtime.run(
    Agent(model: model,
          instructions: "Prepare the weekly report.",
          tools: [WriteReport()]),
    policy: .default.maxTurns(30).budget(tokens: 200_000))

for try await event in run.events { render(event) }

// after a crash or relaunch — the reason the runtime exists:
let resumed = try await runtime.resume(run.id)
```

## 3. Tools: improve Apple's tool calls without owning the tool noun

Decided direction from the 2026-07-18 investigation (SDK findings recorded in
[../research/foundation-models-adaptation.md](../research/foundation-models-adaptation.md)
§ tool protocol): Apple's `Tool` has **no metadata slot**, and sessions take
`[any Tool]` — so the two problems separate:

- **Interception needs no developer-facing API.** The runtime hands the session
  `InstrumentedTool<Base>` wrappers: trace-before-budget, output budgets,
  timeouts, and **corrective error handling** — recoverable thrown errors return
  to the model as structured tool output instead of Apple's default
  response-terminating `ToolCallError`. Every FM tool ever written gets this by
  being run through the runtime, conforming to nothing of ours.
- **Metadata is data, not a type.** One `ToolAnnotations` value (effects,
  idempotency, approval class), supplied by precedence:
  run-policy table → `.annotations(...)` modifier (tools you don't own) →
  optional refinement conformance (`AnnotatedTool: Tool`, your own tools,
  statically checked) → MCP's own hints (`readOnlyHint`/`destructiveHint`/
  `idempotentHint`/`openWorldHint` map directly) → conservative default
  (unannotated = consequential). `RunPolicy.requireAnnotations` turns the
  default into an approval interrupt instead.

This **supersedes the earlier separate host-tool-protocol design** in
[tool-architecture.md](tool-architecture.md) §2: no `AgentTool`-style second tool
world. Work Agent's concrete tools are plain FM tools with annotations. The
increment that builds the tool host updates tool-architecture.md §2 to match.

## 4. Provider posture

Accepted by Toni ("sounds good") on 2026-07-18:

- The runtime accepts **any injected `LanguageModel`** — that is the point of
  building on Apple's protocol. Vendor FM packages (Claude, Gemini) plug in with
  zero runtime code; client-side tool calling through them is verified as
  supported (Anthropic README).
- **We implement executors only where no trustworthy FM package exists** — with
  two standing exceptions: the OpenAI-compatible executor (no OpenAI package
  exists; covers nine curated providers) and our own Anthropic executor (vendor
  package is v0.1/beta/best-effort, its production auth assumes a proxy backend
  rather than BYOK, and failover fidelity requires knowing where state lives).
- **Hugging Face `AnyLanguageModel` is not a provider package** — it's a parallel
  reimplementation of the FM API in its own module; its types don't conform to
  Apple's protocols. Watch, don't bridge.
- **The conformance suite is public API and the ecosystem hook**: the POC's
  scripted-semantics tests generalized, so any model package can be certified
  against the runtime's durability assumptions (cancellation, revert atomicity,
  tool-error behavior, metadata round-trip). Uncertified models run;
  cross-provider failover between uncertified executors is flagged honestly.

## 5. DX commitments

- **Progressive disclosure, one runtime.** The simple call and the advanced host
  observe the same events, checkpoints, and state transitions.
- **Test doubles are first-class public API** — scripted `LanguageModel`s,
  virtual clocks, fixture recorders. Agent apps become *testable*; no framework
  in any language does this well.
- **Strict Swift 6.** Immutable `Sendable` values public, actors for mutable
  coordination, `AsyncSequence` everywhere, typed errors carrying their recovery
  action, no callbacks or stringly-typed anything.
- **No SwiftUI import in the runtime**; a small Observation projection package
  can come later if a real consumer proves it.
- **Macros only where they delete real boilerplate** (a tool-from-function macro
  is the one candidate); never to hide execution or side effects.
- **Docs teach durability patterns** (idempotency, interrupts, resume), not just
  API syntax — the frameworks that won in Python/TS won partly by teaching.
- **Never**: a second transcript type, a wrapper around `Generable`, a "simple
  mode" that is a different engine, or a required cloud account.
