# Plan: ROADMAP item 2 — verify the core, close the gaps

**Status: ready to implement, verified against the tree 2026-07-20.** One code
increment (worktree + PR). Goal: every provider claim becomes a verified fact —
all eleven clouds through a real tool cycle, `web_search` live, Apple's on-device
model through the package path, GLM's auth built. All twelve `.env` keys are
confirmed present (2026-07-19 top-up): `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
`GOOGLE_API_KEY`, `MOONSHOT_API_KEY`, `ZHIPU_API_KEY`, `DEEPSEEK_API_KEY`,
`MINIMAX_API_KEY`, `DASHSCOPE_API_KEY`, `XAI_API_KEY`, `META_MODEL_API_KEY`,
`TINKER_API_KEY`, `BRAVE_API_KEY`. Never print a key, never commit one into a
fixture, scrub any recorded traffic (CLAUDE.md § credentials). If a step
conflicts with the tree, stop and say so; do not improvise.

## 1. Gated live-test infrastructure (new — the old one died with the app)

New test target `ExecutorsLiveTests` in Package.swift (deps: `Executors`,
`ToolKitFiles`, `Recorder`). Gating pattern: swift-testing
`.enabled(if: ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] != nil)`
per test — normal `swift test` runs skip them all silently. Run command,
documented in a comment at the top of the file:

```bash
set -a; source .env; set +a
swift test --filter ExecutorsLiveTests
```

Shared harness, one function: build a `LanguageModelSession` with the given
model + one deterministic tool (`SentinelTool`: `@Generable` empty-ish args,
returns a fixed sentinel string), prompt "Use the sentinel tool, then report
its value verbatim." Assert: the tool was called (a recording flag on the tool),
the final response is non-empty and contains the sentinel — which proves the
full two-request cycle including provider-state replay (DeepSeek's mandatory
reasoning echo etc. fail loudly on request two if broken; that's the point).

## 2. The provider matrix — eleven tests from one harness

| Provider | Endpoint (verified 2026-07-17 unless noted) | Env var | Model |
|---|---|---|---|
| deepseek | `https://api.deepseek.com/chat/completions` (no `/v1`) | DEEPSEEK_API_KEY | `deepseek-v4-pro` |
| anthropic | `https://api.anthropic.com/v1/messages` (AnthropicModel) | ANTHROPIC_API_KEY | `claude-sonnet-5` |
| google | `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` | GOOGLE_API_KEY | `gemini-3.5-flash` |
| moonshotai | `https://api.moonshot.ai/v1/chat/completions` | MOONSHOT_API_KEY | `kimi-k3` |
| alibaba | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions` | DASHSCOPE_API_KEY | `qwen3.7-max` |
| openai | `https://api.openai.com/v1/chat/completions` | OPENAI_API_KEY | `gpt-5.6` |
| minimax | `https://api.minimax.io/v1/chat/completions` | MINIMAX_API_KEY | `MiniMax-M3` |
| zai/GLM | see §3 — auth first | ZHIPU_API_KEY | `glm-5.2` |
| xai | **never probed** — take from a fresh models.dev `api.json` fetch (expect `https://api.x.ai/v1/...`), confirm live | XAI_API_KEY | `grok-4.5` |
| meta | **never probed** — models.dev, confirm live | META_MODEL_API_KEY | `muse-spark-1.1` |
| thinkingmachines | **never probed** — models.dev (OpenAI-compatible per registry), confirm live | TINKER_API_KEY | `inkling` |

For the three never-probed providers: fetch the endpoint from models.dev,
probe, and **record whatever actually happens** — a failing provider stays
failed in the results table with its exact symptom; do not massage it green.

## 3. GLM JWT auth (the eleventh provider's missing piece)

`ZHIPU_API_KEY` is an `id.secret` pair; both GLM hosts 401 on raw bearer
(research/provider-chat-endpoints.md). Implement in
`OpenAICompatibleExecutor.Configuration`: add
`authStyle: AuthStyle = .bearer` with `enum AuthStyle { case bearer, zhipuJWT }`.
For `.zhipuJWT`, compute the header per Zhipu's documented scheme (verify the
exact shape against Zhipu's current docs before coding — this is the
known-community shape, confirm it): split the key at the first `.` into
`id`/`secret`; JWT with header `{"alg":"HS256","sign_type":"SIGN"}`, payload
`{"api_key": id, "exp": <now+1h, ms>, "timestamp": <now, ms>}`, HMAC-SHA256
via CryptoKit, base64url without padding. Try `open.bigmodel.cn/api/paas/v4`
first, `api.z.ai/api/paas/v4` second. **Bounded**: if both still 401 with a
well-formed JWT, stop, record the exact response in the results, and leave GLM
failed — two endpoint attempts, no thrashing. Unit-test the JWT construction
offline (fixed clock injected → exact expected token string).

## 4. `web_search` live (FR-083)

One gated test in `ToolKitWebTests` (or the live target):
`.enabled(if: env["BRAVE_API_KEY"] != nil)` — real query ("Swift Foundation
Models framework"), assert non-empty results with titles + URLs. Check
`WebSearchTool`'s current key-injection seam and use it as built; if the seam
only accepts a stubbed transport, extend minimally.

## 5. Apple on-device model, through the package path

Gated test (`RecorderTests` or live target): guard on
`SystemLanguageModel.default.availability` — anything but available → skip
with the reason in the skip message (no eligible device ≠ failure). When
available: a session with `SystemLanguageModel.default` and one ToolKit tool
(`ReadFile` on a temp fixture), assert a response — proving the package's
tools and instrumentation treat Apple's model like any other `LanguageModel`.
Run it on this Mac; record availability status honestly either way.

## 6. Results recording — the DOD's substance

- **research/provider-chat-endpoints.md**: the probe table updated in place —
  new date column/rows for the tool-cycle results, the three first-ever
  providers added with their endpoints, GLM's outcome. This doc stays the
  provider-facts source of truth.
- **PRODUCT.md**: the executors section's verification claims updated to match
  the new table (verified-with-date list; failures named).
- **ENGINEERING.md**: the live-test infrastructure documented (target, gating,
  run command); GLM `authStyle` in the executors section if built.
- **ROADMAP**: delete item 2, renumber; delete this plan (absorption rule).

## Verification

`swift test` (offline suite) green on macOS + iOS build green — the gated tests
must not run without keys. Then the sourced-env live run, with the pass/fail
matrix pasted into the PR description (statuses and symptoms only — never
response prose, never keys).

## Out of scope

Fixing any provider breakage beyond GLM auth (record as findings → review →
roadmap); CI wiring for live tests (they're key-gated and manual by design);
executor feature work of any kind; touching `fetch_url`/files tools. This
increment turns claims into facts — it does not add capabilities.
