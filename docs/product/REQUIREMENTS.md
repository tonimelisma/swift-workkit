# Work Agent — Requirements

**Status:** Living. Last substantive change: 2026-07-16.

Every behavior change updates this file in the same increment. See
[CLAUDE.md](../../CLAUDE.md) for the rule and the traceability scheme.

## How to read this

Requirements use [EARS](https://alistairmavin.com/ears/) syntax so each one is
individually testable:

- **Ubiquitous** — always true: *The system shall …*
- **State-driven** — *While `<state>`, the system shall …*
- **Event-driven** — *When `<trigger>`, the system shall …*
- **Optional** — *Where `<feature>`, the system shall …*
- **Unwanted** — *If `<condition>`, then the system shall …*

`FR` = functional, `NFR` = non-functional. **IDs are permanent.** Dropped requirements
are marked `Superseded` or `Removed` in place and keep their number forever.

**Status** is one of: `Specified` (agreed, not built), `Implemented` (built, tested,
traced), `Superseded` (replaced — links to its replacement), `Removed`.

Nearly everything here is `Specified`. That is honest: the codebase is an Xcode
template. The status column is how we tell the difference between what we've decided
and what exists.

---

## Model neutrality

The product thesis. See [PRODUCT.md](PRODUCT.md) §1. These are the requirements that
make neutrality structural rather than aspirational — a change that breaks one of these
is a change to what the product is.

| ID | Requirement | Status |
|---|---|---|
| **FR-001** | The system shall perform all model inference through a provider abstraction, such that no feature depends on a specific model vendor. | Specified |
| **FR-002** | The system shall support at minimum one hosted commercial provider and one locally-hosted open model. | Specified |
| **FR-003** | When the user changes provider or model, the system shall continue to expose every capability that does not require a provider-exclusive feature. | Specified |
| **FR-004** | Where a capability requires a provider-exclusive feature, the system shall degrade to a neutral implementation rather than disable the capability. | Specified |
| **FR-005** | The system shall allow the user to supply their own credentials for a provider they already have a relationship with. | Specified |
| **FR-006** | If a provider becomes unavailable mid-task, then the system shall preserve task state and allow resumption on another provider. | Specified |
| **NFR-001** | Adding a new provider shall not require changes outside its adapter and its registration. | Specified |

## Tasks

| ID | Requirement | Status |
|---|---|---|
| **FR-010** | The system shall represent work as a durable task that outlives the conversation that created it. | Specified |
| **FR-011** | The system shall persist tasks locally across app restarts. | Specified |
| **FR-012** | While a task is running, the system shall expose its current status and the action in progress. | Specified |
| **FR-013** | The system shall record, per task, the originating request, the plan, observable progress events, sources consulted, artifacts produced, and the final result. | Specified |
| **FR-014** | When a task cannot fully complete, the system shall preserve and present the work that did succeed alongside a description of what did not. | Specified |
| **FR-015** | The system shall allow the user to stop a running task at any point. | Specified |
| **FR-016** | The system shall not present hidden model reasoning as progress. Progress consists of observable actions, evidence, and decisions. | Specified |

## Approvals

| ID | Requirement | Status |
|---|---|---|
| **FR-020** | The system shall classify actions by effect, not by tool, and require approval based on effect. | Specified |
| **FR-021** | When requesting approval, the system shall present the exact action, its target, the affected data, and whether it is reversible. | Specified |
| **FR-022** | The system shall never request approval solely in terms of a tool or capability name. | Specified |
| **FR-023** | The system shall allow the user to edit a proposed action before approving it. | Specified |
| **FR-024** | While a task waits for approval, the system shall not perform the pending action or any action that depends on it. | Specified |
| **FR-025** | The system shall require approval before any action that sends information outside the Mac to a recipient the user did not name. | Specified |

## Transparency

| ID | Requirement | Status |
|---|---|---|
| **FR-030** | The system shall maintain a local, user-readable record of data accessed, files changed, messages drafted or sent, actions approved, and model calls made. | Specified |
| **FR-031** | The system shall make clear which parts of a task ran locally and which were sent to a model provider. | Specified |
| **FR-032** | The system shall present sources such that the user can inspect the original material behind any result. | Specified |

## Presentation

| ID | Requirement | Status |
|---|---|---|
| **FR-040** | The system shall not surface implementation vocabulary — MCP, JSON-RPC, tool schema, OAuth scope, AXUIElement, XPC — in the normal user interface. | Specified |
| **FR-041** | The system shall describe agent activity in terms of outcomes rather than tool invocations. | Specified |
| **FR-042** | Where technical detail is useful, the system shall place it behind an explicitly advanced surface. | Specified |

## Non-functional

| ID | Requirement | Status |
|---|---|---|
| **NFR-002** | Task state, approvals, permissions, and history shall reside on the Mac and shall not require a service operated by us. | Specified |
| **NFR-003** | The system shall be distributed as a Developer ID–signed, notarized application. (ADR-0003) | Specified |
| **NFR-004** | The system shall not execute arbitrary code on the host Mac outside an isolated environment. | Specified |
| **NFR-005** | Every requirement in this document shall be traceable to code and tests by its ID. (CLAUDE.md § Traceability) | Specified |
| **NFR-006** | The user interface shall remain responsive while a task is running. | Specified |

---

## Deliberately unspecified

Named so their absence reads as a decision rather than an oversight:

- **Connections** (Gmail, Drive, Microsoft 365, Slack). No requirements until we have a
  real task that needs one. Writing them now would be fiction.
- **Native app control** (Accessibility, screen capture). Same. ADR-0003 keeps the door
  open by choosing Developer ID; that's sufficient for now.
- **Automations and scheduling.** Post-engine.
- **Sandboxed code execution.** NFR-004 constrains it; the mechanism is unspecified
  until something needs it.
