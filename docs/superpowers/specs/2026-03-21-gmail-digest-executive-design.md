# Gmail Digest — Executive Email Workflow

**Date:** 2026-03-21
**Status:** Approved

## Problem

An executive checking email twice daily needs a high-ROI digest that:
- Triages volume across EA-labeled folders and raw inbox
- Surfaces time-sensitive items before they go stale
- Provides enough context to act, delegate, or defer without opening individual emails
- Runs automatically at scheduled times

## Solution

A Claude Code skill triggered by cron at 7am and 1pm Pacific that fetches unread Gmail across labeled folders, generates a layered digest with narrative summary, decision queue, and dashboard, and prepares draft replies and delegation suggestions.

## Digest Output Structure

A single `digest.md` with three layers:

### Layer 1: Executive Summary

A narrative paragraph providing situational awareness — what's hot, what's aging, what the landscape looks like. Followed by a triage:

```markdown
# Email Digest — YYYY-MM-DD HH:MM

**Since last check:** N new emails | X need your decision | Y delegatable | Z FYI

## What You Need to Know

[Narrative summary: what's time-sensitive, what's been waiting too long,
what's resolved, what the overall picture looks like. Written in executive
prose, not bullet points. 3-5 sentences.]

**Act on now:** [items with deadlines or aging risk]
**Can delegate:** [items suitable for EA or team]
**Can wait:** [informational, no time pressure]
```

### Layer 2: Decision Queue + Categorized Detail

Organized by label priority:

```markdown
## @Action Now (EA-tagged)
- **Subject** from sender — one-line context
  - 💬 Draft reply: "Ready-to-send response text"
  - 🔀 Delegate to: [person] — "Suggested forwarding note"

## Calendar
- **Subject** — what changed or what's new

## Other Inbox
- **Subject** from sender — one-line context
```

### Layer 3: Dashboard

```markdown
## Dashboard
| Folder      | New | Action Needed | Delegatable | FYI |
|-------------|-----|---------------|-------------|-----|
| @Action Now | N   | N             | N           | N   |
| Calendar    | N   | N             | N           | N   |
| Other Inbox | N   | N             | N           | N   |
| **Total**   | N   | N             | N           | N   |
```

## Authentication

Gmail access is provided via pre-configured MCP tools in the Claude Code environment. Auth (OAuth tokens, refresh) is managed externally by the MCP server — this project does not own credentials. If auth expires, the MCP tool call will fail and the skill reports "Gmail MCP tools not available."

## Label-Aware Fetching

Three sources fetched in priority order:

1. **`@action now`** — EA-curated urgent items. Query: `label:@action-now is:unread`
2. **`Calendar`** — scheduling-related. Query: `label:Calendar is:unread`
3. **Other Inbox** — remainder. Query: `in:inbox is:unread -label:@action-now -label:Calendar`

`max_results` applies per label query (50 each). EA-labeled items are never filtered by exclude_patterns. Exclude patterns only apply to Other Inbox.

## Draft Replies & Delegation

**Draft replies** generated when an email expects or invites a response:
- `@Action Now` items that need a reply or decision
- "Action Needed" items from Other Inbox
- Purely informational alerts get a one-line acknowledgment suggestion instead

Rules:
- Tone: executive, concise, decisive
- Routine approvals/confirmations: one-liner ready to send
- Complex topics: 2-3 sentences with `[FILL]` placeholders for unknowns
- Marked with `💬 Draft reply:` inline

**Delegation suggestions** generated when:
- Action is coordination/scheduling → suggest EA
- Action is technical follow-up → suggest team lead (inferred from thread participants)
- Marked with `🔀 Delegate to:` with suggested forwarding note

Nothing is sent automatically. All suggestions are advisory.

## Classification

Email categorization (Action Needed, Delegatable, FYI) is performed by Claude using LLM judgment on email content and context:

- **Action Needed:** Email expects a response, decision, or approval from the user
- **Delegatable:** Action is needed but could be handled by EA or a team member
- **FYI:** Informational — no response expected (shares, notifications, RSVPs, reports)

`@Action Now` items inherit "Action Needed" by default (EA already triaged). Claude further classifies whether they are also delegatable.

## Scheduling & Automation

Two macOS launchd jobs (installed via `cron/setup.sh`), which reads schedule and timezone from `config.json`:

- **7:00 AM Pacific** — morning digest
- **1:00 PM Pacific** — afternoon digest

Each run:
1. Executes `claude -p "/gmail-digest"`
2. Produces fresh `digest.md` (replaces previous)
3. Individual messages accumulate in `messages/` (pruned after 30 days)
4. If machine is asleep at trigger time, launchd runs on next wake

## Config

`config.json`:
```json
{
  "labels": ["@action now", "Calendar"],
  "exclude_patterns": ["notifications@github.com", "noreply@", "[bot]"],
  "max_results": 50,
  "schedule": ["07:00", "13:00"],
  "timezone": "America/Los_Angeles"
}
```

## Project Structure

```
gmail-digest/
├── config.json
├── .processed.json
├── .gitignore
├── digest.md              ← what you read (generated)
├── messages/              ← individual emails as markdown (headers + body), used for reference and thread context
├── skills/
│   └── gmail-digest.md   ← the Claude Code skill
├── cron/
│   └── setup.sh          ← installs launchd jobs
└── docs/
    └── superpowers/specs/
        └── 2026-03-21-gmail-digest-executive-design.md
```

## Processed State

`.processed.json` tracks fetched message IDs to avoid duplicates:
```json
{
  "last_run": "2026-03-21T07:00:00Z",
  "processed": { "messageId": "YYYY-MM-DD" }
}
```
Entries older than 30 days are pruned on each run.

## Skill Responsibilities

The `skills/gmail-digest.md` skill orchestrates the full workflow when invoked:

1. Load config from `config.json` (validate required fields: `labels`, `timezone`)
2. Load and prune `.processed.json`; prune `messages/` files older than 30 days
3. Fetch unread emails per label (using Gmail MCP tools)
4. Filter Other Inbox with exclude_patterns
5. Deduplicate against processed state
6. Fetch full message content for each new email
7. Classify each email (Action Needed / Delegatable / FYI) using LLM judgment
8. Generate draft replies and delegation suggestions where appropriate
9. Save individual messages to `messages/`
10. Write `digest.md` with all three layers
11. Update `.processed.json`

## Error Handling

- **MCP tools unavailable:** Report error, stop.
- **Network failure mid-batch:** Save what was fetched, report partial results.
- **Malformed config:** Report error, offer to recreate defaults.
- **Malformed .processed.json:** Report error, recreate empty state.
- **No unread messages:** Write brief digest noting no new mail since last check.
- **Machine asleep at trigger:** launchd catches up on wake.
- **File corruption:** All file writes (`.processed.json`, `digest.md`) use atomic temp-file-then-rename to prevent partial writes.
