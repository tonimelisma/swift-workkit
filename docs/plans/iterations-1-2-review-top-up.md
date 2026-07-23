# Plan: iterations 1–2 review top-up

**Written:** 2026-07-22, after re-reviewing PRs #13–#15 against the renamed
`swift-workkit` tree and rerunning the live matrix with Xcode 27.

The earlier review's code findings were fixed by PR #15. This final pass found
three small pieces of errata and one changed external fact. No product decision
is open.

## Work

1. In `Sources/ToolKitWeb/NetworkSafety.swift`, replace the Xcode 27-deprecated
   `String(cString:)` conversion with an explicit decode of the bytes preceding
   the first null terminator. Preserve the resolver's behavior.
2. In `Tests/ExecutorsTests/OpenAIResponsesTests.swift`, remove the unnecessary
   `try` that Xcode 27 now diagnoses.
3. Correct `docs/engineering/ENGINEERING.md` from 110 to 131 discovered tests.
4. Correct the Thinking Machines preset using the provider's official
   documentation and a direct two-leg probe:
   - model ID: `thinkingmachines/Inkling` (case-sensitive);
   - endpoint: the Anthropic-compatible
     `https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api/v1/messages`,
     not the OpenAI-compatible endpoint intended for `tinker://` sampler
     checkpoint paths;
   - generalize `AnthropicModel`/`AnthropicExecutor.Configuration` with
     defaulted `providerID` and `endpoint` values, keeping the existing Anthropic
     API source-compatible, and use the configured provider ID for diagnostics,
     transcript metadata ownership, and same-provider reasoning replay;
   - move the Thinking Machines live test to that executor and add offline
     configuration/encoding coverage.
5. Record the 2026-07-22 live result everywhere it changes current truth:
   GLM now completes the full tool cycle; re-run Thinking Machines through the
   corrected preset; remove resolved account actions from
   `docs/product/ROADMAP.md`; update `README.md`,
   `docs/product/PRODUCT.md`, `docs/engineering/ENGINEERING.md`, and
   `docs/research/provider-chat-endpoints.md` with only the measured outcome.

No new FR/NFR is minted: the provider-neutral executor requirement already
covers configurable providers, and this corrects a broken preset rather than
adding a capability.

## Verification

- Clean the renamed repository's derived build products so no stale
  `/Development/Work Agent/` paths remain.
- `swift test`
- `xcodebuild -scheme WorkKit-Package -destination 'generic/platform=iOS' build`
- With `.env` sourced:
  `swift test --filter 'ExecutorsLiveTests|WebSearchLiveTests'`
- `git diff --check`

After the code increment merges, delete this consumed plan in the same PR.
