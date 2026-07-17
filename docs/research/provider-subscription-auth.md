# Can a third-party app use someone's LLM subscription?

**Last verified:** 2026-07-16
**Why we looked:** Toni asked for ChatGPT **subscription** auth alongside API keys, and
asked whether the same model works for other providers. PRODUCT.md §1 rests partly on
"users already pay for a subscription and shouldn't pay again per app."

## Finding: no. Not from any major provider, and it's getting worse, not better.

**Short version: subscription OAuth is reserved for each vendor's own first-party apps.
Two of the three majors have explicitly closed it to third parties and enforce that with
account bans. The third has never permitted it and its docs describe the flow as
first-party-only.**

| Provider | Third-party subscription auth | Evidence |
|---|---|---|
| **Anthropic** | **Explicitly banned. Enforced.** | OAuth "is intended exclusively for Claude Code and Claude.ai." Using Free/Pro/Max OAuth tokens "in any other product, tool, or service constitutes a violation of Anthropic's Consumer Terms." Enforced since early 2026 — accounts suspended, without notice. Equivalent access removed ~April 2026. |
| **Google** | **Closed.** | Made the same change to Gemini CLI. |
| **OpenAI** | **Undocumented, unsanctioned, ambiguous.** | Docs describe sign-in for "the ChatGPT desktop app, Codex CLI, and IDE extension" — OpenAI's own products only. No partner program, no allowlist, no third-party path documented. |

### How the tools that do it anyway actually work

Third-party tools (e.g. OpenClaw) take the Codex OAuth token, **run a localhost proxy,
and translate requests into the Codex CLI's shape so OpenAI's auth check passes**, with
the user's ChatGPT subscription paying.

That is impersonating a first-party client to defeat an auth check. Not a grey area of
interpretation — the mechanism only works *because* it lies about what it is. It is also
exactly what Anthropic and Google shut down. Treating OpenAI's silence as permission is
betting the product on a door nobody has closed *yet*.

### What this costs us if we do it anyway

- **It's our users who get banned, not us.** Anthropic suspends the *account*. We'd be
  shipping a feature to non-technical people whose foreseeable outcome is losing their
  Claude or ChatGPT subscription. They would have no idea they'd taken that risk.
- **Permanent cat-and-mouse.** The mechanism depends on a proxy mimicking a client we
  don't control. Every Codex CLI release can break it.
- **It poisons the legitimate path.** A vendor that sees us impersonating its CLI is not
  a vendor that gives us a partnership later.

### What this means for the thesis

PRODUCT.md §1 plank 3 — *"users already pay for a model subscription and don't want to
pay again per app; a ChatGPT or Claude subscription should just work"* — **is not
available.** Not "hard," not "later." The vendors have decided their subscriptions are
for their own clients, and two of them enforce it.

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

- **Whether OpenAI would sanction it via partnership.** No public program exists; docs
  say to contact them. Unknown, and worth asking rather than assuming.
- **Enterprise/Team plans.** All findings above concern consumer plans. Not investigated.
- **Whether any provider offers a legitimate BYO-subscription path** for third parties.
  Not found for the majors; smaller providers unexamined.

## Sources

- [Anthropic — Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)
- [Anthropic bans Claude subscription OAuth in third-party apps (Feb 2026)](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/)
- [A Claude Code subscription is not a developer credential](https://yage.ai/share/claude-code-subscription-not-a-developer-credential-en-20260321.html)
- [OpenAI Codex auth docs](https://learn.chatgpt.com/docs/auth) · [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- [OpenAI Services Agreement](https://openai.com/policies/services-agreement/)
