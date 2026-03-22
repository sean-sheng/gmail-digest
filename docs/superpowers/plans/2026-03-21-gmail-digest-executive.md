# Gmail Digest — Executive Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the existing gmail-digest skill from a simple unread email fetcher into a label-aware, executive-focused digest with narrative summaries, draft replies, delegation suggestions, and cron automation.

**Architecture:** A Claude Code skill (`skills/gmail-digest.md`) orchestrates the workflow using Gmail MCP tools. Config drives label queries and filtering. Output is a layered `digest.md`. Two macOS launchd plist files provide scheduled automation.

**Tech Stack:** Claude Code skill (markdown prompt), Gmail MCP tools, macOS launchd, bash

**Spec:** `docs/superpowers/specs/2026-03-21-gmail-digest-executive-design.md`

---

### Task 1: Update config.json to new schema

**Files:**
- Modify: `config.json`

- [ ] **Step 1: Update config.json**

Replace the current `important_senders`-based config with the label-based schema:

```json
{
  "labels": ["@action now", "Calendar"],
  "exclude_patterns": ["notifications@github.com", "noreply@", "[bot]"],
  "max_results": 50,
  "schedule": ["07:00", "13:00"],
  "timezone": "America/Los_Angeles"
}
```

- [ ] **Step 2: Verify config.json is valid JSON**

Run: `cat ~/development/gmail-digest/config.json | python3 -m json.tool`
Expected: Pretty-printed JSON with no errors

- [ ] **Step 3: Commit**

```
/commit
```

---

### Task 2: Rewrite the gmail-digest skill — Config & State Loading

**Files:**
- Modify: `skills/gmail-digest.md`

This task rewrites the top portion of the skill: frontmatter, description, arguments, config schema, and processed state handling. The existing skill file is the starting point.

- [ ] **Step 1: Rewrite frontmatter and description**

Replace the existing frontmatter and opening section. The skill description should reflect the new executive digest purpose. Keep `$ARGUMENTS` as optional sender filter.

- [ ] **Step 2: Rewrite Config section**

Replace the config schema to match the new `config.json` format (labels-based, with schedule and timezone fields). Add validation: required fields are `labels` and `timezone`.

- [ ] **Step 3: Rewrite Processed State section**

Keep the same `.processed.json` structure but add:
- Prune `messages/` files older than 30 days (not just JSON entries)
- Handle malformed `.processed.json` by recreating empty state

- [ ] **Step 4: Verify the file is well-formed markdown**

Read the file and check for syntax issues.

- [ ] **Step 5: Commit**

```
/commit
```

---

### Task 3: Rewrite the gmail-digest skill — Label-Aware Fetching & Filtering

**Files:**
- Modify: `skills/gmail-digest.md`

- [ ] **Step 1: Rewrite the Search Gmail section**

Replace the single query approach with label-aware fetching:

1. If `$ARGUMENTS` is a sender email: use `gmail_search_messages` with `from:$ARGUMENTS is:unread` (unchanged behavior)
2. Otherwise, fetch three sources in priority order:
   - For each label in `config.labels`: `label:{label-slug} is:unread` with `maxResults` from config
   - Other Inbox: `in:inbox is:unread -label:{label1-slug} -label:{label2-slug}` with `maxResults` from config
   - Label slugs: lowercase, spaces replaced with hyphens (e.g., `@action now` → `@action-now`)
3. Paginate each query if `nextPageToken` returned and fewer than `max_results` collected

- [ ] **Step 2: Rewrite the Filter section**

- EA-labeled items (`@action now`, `Calendar`) are never filtered by exclude_patterns
- `exclude_patterns` only apply to Other Inbox emails
- Case-insensitive substring match against full `From` header

- [ ] **Step 3: Update the Deduplicate section**

Keep existing logic: remove messages whose IDs are already in `.processed.json`.

- [ ] **Step 4: Update the "no new messages" handling**

If no new messages found across all sources: write a brief `digest.md` noting "No new emails since last check at [last_run time]." Update `last_run`. Stop.

- [ ] **Step 5: Commit**

```
/commit
```

---

### Task 4: Rewrite the gmail-digest skill — Message Fetching & Individual Saves

**Files:**
- Modify: `skills/gmail-digest.md`

- [ ] **Step 1: Rewrite the "Fetch and save each message" section**

Keep the existing per-message format (subject, from, to, cc, date, body table + body content) but add:
- Track which label/source each message came from (needed for digest categorization)
- HTML stripping, 10,000 char truncation, attachment notes — all unchanged
- Slugify logic unchanged
- File path: `messages/YYYY-MM-DD-slug-messageId8chars.md`
- Add message ID to processed state after successful write
- Use atomic write (write to `.tmp` file, then rename)

- [ ] **Step 2: Commit**

```
/commit
```

---

### Task 5: Rewrite the gmail-digest skill — Classification & Draft Replies

**Files:**
- Modify: `skills/gmail-digest.md`

- [ ] **Step 1: Add Classification section**

After fetching all messages, classify each email using LLM judgment:

- **Action Needed:** Email expects a response, decision, or approval
- **Delegatable:** Action needed but could be handled by EA or team member
- **FYI:** Informational, no response expected

`@Action Now` labeled items inherit "Action Needed" by default. Claude further determines if delegatable.

- [ ] **Step 2: Add Draft Replies section**

For emails classified as "Action Needed":
- Generate a draft reply inline
- Tone: executive, concise, decisive
- Routine approvals: one-liner
- Complex topics: 2-3 sentences with `[FILL]` placeholders
- Purely informational alerts: one-line acknowledgment instead
- Mark with `💬 Draft reply:`

- [ ] **Step 3: Add Delegation Suggestions section**

For emails classified as "Delegatable":
- Coordination/scheduling → suggest EA
- Technical follow-up → suggest team lead (inferred from thread participants)
- Mark with `🔀 Delegate to:` with suggested forwarding note

- [ ] **Step 4: Commit**

```
/commit
```

---

### Task 6: Rewrite the gmail-digest skill — Digest Output (Three Layers)

**Files:**
- Modify: `skills/gmail-digest.md`

This is the core output — replaces the old `summary.md` section. Output file changes from `summary.md` to `digest.md`.

- [ ] **Step 1: Write Layer 1 — Executive Summary**

```markdown
# Email Digest — YYYY-MM-DD HH:MM

**Since last check:** N new emails | X need your decision | Y delegatable | Z FYI

## What You Need to Know

[Narrative summary: 3-5 sentences. What's time-sensitive, what's aging,
what's resolved, overall landscape. Executive prose, not bullets.]

**Act on now:** [items with deadlines or aging risk]
**Can delegate:** [items suitable for EA or team]
**Can wait:** [informational, no time pressure]
```

- [ ] **Step 2: Write Layer 2 — Decision Queue + Categorized Detail**

One section per label in config order, plus "Other Inbox":

```markdown
## @Action Now (EA-tagged)
- **Subject** from sender — one-line context
  - 💬 Draft reply: "response text"
  - 🔀 Delegate to: [person] — "forwarding note"

## Calendar
- **Subject** — what changed or what's new

## Other Inbox
- **Subject** from sender — one-line context
```

- [ ] **Step 3: Write Layer 3 — Dashboard**

```markdown
## Dashboard
| Folder      | New | Action Needed | Delegatable | FYI |
|-------------|-----|---------------|-------------|-----|
| @Action Now | N   | N             | N           | N   |
| Calendar    | N   | N             | N           | N   |
| Other Inbox | N   | N             | N           | N   |
| **Total**   | N   | N             | N           | N   |
```

- [ ] **Step 4: Specify atomic write for digest.md**

Write to `digest.md.tmp` then rename to `digest.md`.

- [ ] **Step 5: Update the "Save processed state" and "Report results" sections**

- Save `.processed.json` with atomic write
- Report: "Fetched N emails. Digest at ~/development/gmail-digest/digest.md"

- [ ] **Step 6: Commit**

```
/commit
```

---

### Task 7: Rewrite the gmail-digest skill — Error Handling

**Files:**
- Modify: `skills/gmail-digest.md`

- [ ] **Step 1: Replace the Error Handling section**

```markdown
## Error Handling

- **MCP tools unavailable**: Report "Gmail MCP tools not available. Ensure you're logged in." Stop.
- **Network failure mid-batch**: Save what was fetched. Update processed state for those. Write partial digest. Report partial results.
- **Malformed config.json**: Report error. Validate required fields (`labels`, `timezone`). Offer to recreate with defaults.
- **Malformed .processed.json**: Report error. Recreate with `{"last_run": null, "processed": {}}`.
- **No unread messages**: Write brief digest noting no new mail since last check.
- **File write failure**: Report error, skip that message, continue with remaining.
- **Atomic writes**: All file writes (`.processed.json`, `digest.md`) write to a `.tmp` file first, then rename.
```

- [ ] **Step 2: Commit**

```
/commit
```

---

### Task 8: Create cron/setup.sh — launchd automation

**Files:**
- Create: `cron/setup.sh`

- [ ] **Step 1: Write setup.sh**

The script should:
1. Read `schedule` and `timezone` from `config.json` using python3 (available on macOS)
2. Generate a macOS launchd plist file `com.gmail-digest.morning.plist` and `com.gmail-digest.afternoon.plist`
3. Each plist runs: `claude -p "/gmail-digest"` with `WorkingDirectory` set to `~/development/gmail-digest`
4. Install to `~/Library/LaunchAgents/`
5. Load both with `launchctl load`
6. Print confirmation with next scheduled run times

Key plist settings:
- `StartCalendarInterval` with `Hour` and `Minute` from config
- `EnvironmentVariables` with `TZ` from config timezone
- `StandardOutPath` and `StandardErrorPath` to `~/development/gmail-digest/cron/logs/`
- Working directory: `~/development/gmail-digest`

- [ ] **Step 2: Make setup.sh executable**

Run: `chmod +x ~/development/gmail-digest/cron/setup.sh`

- [ ] **Step 3: Test setup.sh parses config correctly (dry run)**

Run: `cd ~/development/gmail-digest && bash cron/setup.sh --dry-run`

The `--dry-run` flag should print the generated plist XML without installing it.

- [ ] **Step 4: Commit**

```
/commit
```

---

### Task 9: Update .gitignore and project hygiene

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Update .gitignore**

Ensure these are ignored:
```
.processed.json
digest.md
summary.md
messages/
cron/logs/
.DS_Store
.claude/
*.tmp
```

- [ ] **Step 2: Remove old summary.md from tracking if present**

Run: `git rm --cached summary.md 2>/dev/null || true`

- [ ] **Step 3: Commit .gitignore changes**

```
/commit
```

---

### Task 10: Manual end-to-end test

**Files:** None (verification only)

- [ ] **Step 1: Run the skill manually**

Run: `/gmail-digest`

- [ ] **Step 2: Verify digest.md output**

Check that `~/development/gmail-digest/digest.md` contains:
- Layer 1: Executive summary with narrative and triage
- Layer 2: Categorized sections for @Action Now, Calendar, Other Inbox
- Layer 3: Dashboard table with counts
- Draft replies on actionable items
- Delegation suggestions where appropriate

- [ ] **Step 3: Verify individual messages saved**

Check that `~/development/gmail-digest/messages/` has new `.md` files with correct format.

- [ ] **Step 4: Verify .processed.json updated**

Check that `.processed.json` has `last_run` timestamp and new message IDs.

- [ ] **Step 5: Run a second time to verify deduplication**

Run: `/gmail-digest`
Expected: "No new emails since last check" or only truly new emails.

---

### Task 11: Create GitHub repository

**Files:** None (git operations only)

- [ ] **Step 1: Create GitHub repo**

Run: `gh repo create gmail-digest --private --source=. --push`

- [ ] **Step 2: Verify repo exists**

Run: `gh repo view gmail-digest`
