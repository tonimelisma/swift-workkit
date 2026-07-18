# Can a third-party app use someone's LLM subscription?

**Last verified:** 2026-07-16 (OpenAI OAuth mechanism traced in full)
**Why we looked:** Toni asked for ChatGPT **subscription** auth alongside API keys, and
asked whether the same model works for other providers. PRODUCT.md §1 rests partly on
"users already pay for a subscription and shouldn't pay again per app."

## Finding: Anthropic bans it. Google closed it. OpenAI is genuinely unclear.

**Correction (2026-07-16):** an earlier version of this doc lumped OpenAI in with
Anthropic under a flat "no." That overstated the evidence. Anthropic's is an explicit,
enforced ban. OpenAI's is *absence of documented permission*, which is a weaker and
materially different thing. Toni asked specifically about GPT — the ambiguous case, not
the banned one.

**Short version: Anthropic and Google have closed third-party subscription OAuth, with
Anthropic enforcing via account suspension. OpenAI has neither permitted nor prohibited
it — its docs simply describe the flow for its own clients. The claim that OpenAI
"explicitly supports" it traces to OpenClaw's own docs and cites nothing.**

| Provider | Third-party subscription auth | Evidence |
|---|---|---|
| **Anthropic** | **Explicitly banned. Enforced.** | OAuth "is intended exclusively for Claude Code and Claude.ai." Using Free/Pro/Max OAuth tokens "in any other product, tool, or service constitutes a violation of Anthropic's Consumer Terms." Enforced since early 2026 — accounts suspended, without notice. Equivalent access removed ~April 2026. |
| **Google** | **Closed.** | Made the same change to Gemini CLI. |
| **OpenAI** | **Undocumented. Not banned. Ambiguous.** | Docs describe sign-in for "the ChatGPT desktop app, Codex CLI, and IDE extension" — their own products. No partner program, no allowlist, no third-party path — but also no prohibition. OpenClaw's docs claim OpenAI "explicitly supports" third-party subscription OAuth, citing nothing. See below. |

### OpenClaw's claim, examined

Toni cited [docs.openclaw.ai/providers/openai](https://docs.openclaw.ai/providers/openai):
> "OpenAI explicitly supports subscription OAuth usage in external tools and workflows like OpenClaw."

Fetched and checked on 2026-07-16. The page provides **no link to any OpenAI policy,
announcement, or statement**, no citation beyond the assertion, and **no risk or ToS
caveat of any kind**. It describes the mechanism as Codex subscription OAuth sign-in
routed "through either the native Codex app-server harness or OpenClaw's embedded
runtime."

This is a third party asserting a second party's policy, with a commercial interest in
that assertion, and no source. It is not evidence about OpenAI's position. It is also
not evidence *against* it — OpenAI genuinely hasn't said. The honest state is: unknown.

### How the OpenAI Codex OAuth flow actually works

Researched 2026-07-16 across the Codex CLI's documented behaviour and several
reverse-engineering write-ups (sources below). This is the mechanism in full.

**The sign-in (OAuth 2.0 + PKCE, exactly as a native app does it):**

1. The client generates a PKCE verifier/challenge pair and starts a loopback HTTP
   server on **`localhost:1455`**.
2. It opens the browser to **`https://auth.openai.com/oauth/authorize`** with the
   **public client id `app_EMoamEEZ73f0CkXaXp7hrann`** — OpenAI's Codex client — and
   redirect `http://localhost:1455/auth/callback`.
3. The user signs into ChatGPT in the browser. The callback returns an auth code.
4. The client exchanges the code at **`https://auth.openai.com/oauth/token`** for an
   **`id_token`** (JWT), an **`access_token`** (an OAuth token, *not* an API key), and a
   **`refresh_token`**. The **`chatgpt_account_id`** is parsed out of the `id_token` JWT.
5. Credentials are cached (Codex uses `~/.codex/auth.json`, plaintext, or the OS
   credential store).

**The inference call:**

- Endpoint: **`https://chatgpt.com/backend-api/codex/responses`** — the Responses API
  shape, on ChatGPT's backend, **not** `api.openai.com`.
- `Authorization: Bearer <access_token>`, plus the account id and the headers/User-Agent
  the Codex backend expects.
- The access token expires in hours; refresh before expiry via the token endpoint with
  the `refresh_token` and the same client id.

**The crux — OpenAI segregates by endpoint and token type.** A subscription OAuth token
works *only* against `chatgpt.com/backend-api/codex`; it fails on the normal
`api.openai.com/v1/...`. And an ordinary API key fails on the Codex backend. So there is
no "use your subscription against the normal API" path. The **only** way to bill a
subscription is to present as the Codex client — its client id, its endpoint, its
expected headers.

**There are two variants**, differing only in where the token comes from:
- **Piggyback:** reuse the `~/.codex/auth.json` that an installed official Codex CLI
  already created.
- **Own flow:** run the PKCE flow yourself using OpenAI's public Codex client id, then
  hit the Codex backend directly. (OpenClaw's localhost-proxy approach is one packaging
  of this.)

### How much of a "hack" is this, really — a correction to my earlier framing

Earlier in this project I called this "impersonating a first-party client to defeat an
auth check… it lies about what it is," and used that to say I wouldn't build it. That was
too strong, and the Cline data point below is why I'm walking it back.

- The flow uses OpenAI's **public** OAuth client with **PKCE** — the standard design for
  native/CLI clients precisely because the client id is not a secret. Using it is not the
  same as stealing a private credential.
- **[Cline](https://cline.bot/blog/introducing-openai-codex-oauth) — a funded, public dev-tools company — ships this openly** and markets it as
  "sign in with your OpenAI account and instantly access all the models you're already
  paying for." So do Cline's, EvanZhou's `openai-oauth`, and community OpenCode plugins.
  This is not a fringe exploit.

So the honest characterization is narrower than "it lies": **there is no sanctioned
third-party path, so the only way to use a subscription is to present as the Codex
client.** Whether that's "fine, it's a public client" or "outside intended use" is
exactly what OpenAI hasn't said.

### What it would cost us — measured, not asserted

- **The exposure lands on the user's account.** The gist reverse-engineering this states
  the licensing plainly: *"subscription auth is licensed for interactive Codex/ChatGPT
  usage, not backend services,"* and misuse can trigger *"rate-limiting, suspension, or
  termination."* OpenAI has not been observed enforcing this against third-party apps the
  way Anthropic has — but the consequence, if they choose to, is the user's subscription,
  not ours. For a non-technical user who won't understand the risk, that matters.
- **Even the vendors doing it claim no permission.** Cline ships it and markets the UX,
  but its announcement contains **zero** reference to OpenAI approval, no quote, no
  partnership, and no risk disclosure. OpenClaw asserts "OpenAI explicitly supports" it
  and cites nothing. So the ecosystem doing this provides *no* evidence OpenAI permits
  it — they simply do it and don't discuss the risk.
- **It tracks a client we don't control.** We'd pin to Codex's client id, endpoint, and
  expected headers. An OpenAI change to any of those breaks us with no notice — the same
  fragility that makes it a maintenance liability, separate from the policy question.
- **`auth.json` is password-equivalent.** However we store the tokens, they grant use of
  the user's paid account until revoked. That is a real secret-handling obligation.

None of these is automatically disqualifying. Cline decided the tradeoff was worth it.
The point is that the decision has these specific costs, not that it's free.

### What this means for the thesis

PRODUCT.md §1 plank 3 — *"users already pay for a model subscription and don't want to
pay again per app; a ChatGPT or Claude subscription should just work"* — **is at best
partially available.** The Claude half is banned outright. The ChatGPT half is
undocumented and unsourced. A plank that rests on one vendor's silence is not a plank.

This does not kill the product. Planks 1 and 2 are untouched, and the wedge survives in
its stronger form: **no vendor's own app will ever let you swap to a competitor's
model.** Cowork will never offer GPT. ChatGPT Work will never offer Claude. We can offer
both. That is a real, permanent, structural advantage — it just gets paid for with API
keys rather than a subscription the user already has.

The honest cost: BYO-API-key is a worse onboarding story than BYO-subscription for
exactly the non-technical audience in PRODUCT.md §2. "Paste an API key" is a real wall
for someone who doesn't know what one is. That's a genuine product problem and it should
be solved as a product problem, not by impersonating someone's CLI.

## Open

- **Exact header set the Codex backend requires.** Sources confirm `Authorization: Bearer`
  and that the account id and Codex-shaped headers/User-Agent matter, but did not pin the
  exact header names (`ChatGPT-Account-Id`? `originator`?). Would need to be captured from
  the real client before building.
- **Whether OpenAI sanctions it via partnership.** No public program; docs say contact
  them. Worth *asking OpenAI directly* rather than inferring from silence or from
  OpenClaw's word.
- **What OpenAI's rate limits are** on a subscription vs an API key for agentic loads —
  materially affects whether this is even a good experience.
- **Enterprise/Team plans.** Findings concern consumer plans.

## Sources

- [Anthropic — Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)
- [Anthropic bans Claude subscription OAuth in third-party apps (Feb 2026)](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/)
- [A Claude Code subscription is not a developer credential](https://yage.ai/share/claude-code-subscription-not-a-developer-credential-en-20260321.html)
- [OpenAI Codex auth docs](https://learn.chatgpt.com/docs/auth) · [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- [OpenAI Services Agreement](https://openai.com/policies/services-agreement/)
- [OpenAI Codex authentication docs](https://learn.chatgpt.com/docs/auth)
- [Cline — bring your ChatGPT subscription (Codex OAuth)](https://cline.bot/blog/introducing-openai-codex-oauth)
- [Codex CLI OAuth token reuse — how it works + why it's risky (gist)](https://gist.github.com/ravidsrk/4e72b774c044917cd260560ec5831e1d)
- [Codex CLI authentication flows and credential management](https://codex.danielvaughan.com/2026/04/01/codex-cli-authentication-flows-credential-management/)
- [EvanZhouDev/openai-oauth](https://github.com/EvanZhouDev/openai-oauth) · [OpenCode issue #3281 — sign-in with ChatGPT](https://github.com/anomalyco/opencode/issues/3281)
