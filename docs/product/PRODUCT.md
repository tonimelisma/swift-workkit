# Work Agent — Product

**Status:** Living. Last substantive change: 2026-07-16.

This doc holds the bet: what we're building, for whom, why it can exist, and what it
is not. Testable statements live in [REQUIREMENTS.md](REQUIREMENTS.md). Sequencing
lives in [ROADMAP.md](ROADMAP.md).

---

## 1. The thesis

Every serious agent product today is welded to the model company that ships it. Claude
Cowork is Anthropic's. ChatGPT Work is OpenAI's. Both will be good. Both are structurally
incapable of being neutral, because neutrality would undermine the thing they're selling.

We're betting that:

- **Inference commoditizes.** The gap between frontier and good-enough narrows, open
  models get genuinely usable for real work, and price per token keeps collapsing.
- **The app layer is where the durable value ends up** — the interaction model, the
  trust model, the memory, the integrations, the judgment about what to show a user
  and when to ask.
- **Users already pay for a model subscription** and don't want to pay again per app.
  A ChatGPT or Claude subscription, or a local model, should just work.

If that's right, an app that innovates independently of any model vendor wins ground
that the vendors' own apps cannot contest. If it's wrong — if one model runs away with
it and vertical integration wins — this product is worse than a wrapper.

That's the bet. It's stated plainly so we can notice if it stops being true.

**The consequence for engineering:** model neutrality is not a feature to add later. Any
decision that couples us to a single provider is wrong by default and needs an ADR to
become right.

---

## 2. Who this is for

**Not developers. Not power users.** People who have work to do and no interest in how
it gets done.

Distribution follows a deliberate path, and scope grows with it:

| Stage | User | What that means for scope |
|---|---|---|
| Now | Toni | Approvals exist as a safety net, not a compliance story. No onboarding polish, no multi-account, no enterprise policy. |
| Later | Friends | Onboarding must work without the author present. Failure states must explain themselves. |
| Eventually | Public | Trust model, permission explanation, recovery, and support all become load-bearing. |

We build for stage 1 and avoid decisions that make stages 2 and 3 impossible. We do
**not** build stage 3's features now. When something claims to be needed "for later,"
that's a roadmap item, not this increment.

The user should never need to know what MCP, AppleScript, Accessibility, XPC, OAuth
scopes, tool schemas, or a sandbox runtime are. If those words appear in the normal UI,
we've failed.

---

## 3. What it is

A native macOS application that:

- runs agent orchestration **locally**, on the user's Mac;
- talks to **whatever model the user chose** — a cloud provider they already subscribe
  to, an API key they own, or a model running on their own hardware;
- does real work against local files, native Mac applications, and connected services;
- keeps permissions, task state, approvals, and history on the Mac;
- makes what it did legible after the fact.

## 4. What it is not

- A wrapper around one vendor's model.
- A developer console, or a GUI for editing MCP JSON.
- A terminal coding agent.
- A chatbot that forgets the work when the conversation ends.
- A remote desktop.

## 5. Product principles

1. **Work, not chat.** The durable unit is a task, not a conversation.
2. **Model neutrality is structural.** Not a setting bolted on at the end.
3. **Show outcomes, not tool calls.** "Found the meeting notes and two related emails,"
   not `Called notes.search`.
4. **Consequential actions are concrete and reviewable.** Never "Allow this tool?" —
   always the exact action, the target, the data, and whether it can be undone.
5. **Local-first, and say so.** The user should be able to tell what left the Mac.
6. **Partial completion beats a generic error.** Knowledge work fails partially; preserve
   what worked.
7. **Calm and native.** No anthropomorphic assistant. macOS patterns, restrained color,
   obvious stop controls.

---

## 6. Current non-goals

Explicit, so they don't get smuggled in:

- Multi-user, teams, or enterprise policy.
- A plugin marketplace.
- Exposing local capabilities to external agents (the draft's "cloud gateway").
- Mac App Store distribution — see ADR-0003.
- Arbitrary shell execution on the host Mac.
- Mobile or web companion.

---

## 7. Open questions

These are unresolved and blocking nothing yet. They get answered before the increment
that depends on them.

- **Minimum macOS version.** 26 buys modern SwiftUI and Foundation Models with no
  availability plumbing; 15 broadens reach at a real cost. Undecided.
- **Background execution.** Does work survive the window closing in v1? Deciding "yes"
  later costs a painful retrofit; deciding "yes" now costs XPC and a LaunchAgent before
  the product is validated.
- **The first real task.** Deferred to increment 6, deliberately. It gets picked once we
  have a working app that talks to an LLM and a set of tools we've actually tested — so
  the choice is made against what the thing demonstrably does, not against imagination.
  The risk this carries, and what bounds it, is in ROADMAP.md.
- **The increment-4 starter tool set.** Which tools exist determines which tasks are
  available to pick from, so this quietly constrains the product. See ROADMAP.md.
- **What "neutral" means mechanically.** Adapter per provider, OpenAI-compatible
  endpoint, or a proxy layer. This is the subject of the increment-2 research spike and
  ADR-0005.
