---
name: gmail-digest
description: Fetch unread emails from Gmail by label, classify by urgency, generate executive digest with draft replies and delegation suggestions. Use when user wants to check email, fetch Gmail, or generate an email digest.
---

# Executive Gmail Digest

Fetch unread emails from Gmail via MCP tools, organized by EA-assigned labels. Produces a layered digest with narrative summary, decision queue with draft replies, delegation suggestions, and a dashboard.

## Arguments

- `$ARGUMENTS` — optional sender email filter (e.g., `sean.sheng@unity3d.com`). If provided, fetch only from that sender. If empty, use label-based fetching from config.

## Config

Config file: `~/development/gmail-digest/config.json`

```json
{
  "labels": ["@action now", "Calendar"],
  "exclude_patterns": ["notifications@github.com", "noreply@", "[bot]"],
  "max_results": 50,
  "schedule": ["07:00", "13:00"],
  "timezone": "America/Los_Angeles"
}
```

If config.json doesn't exist, create it with the defaults above. Validate required fields: `labels`, `timezone`. If either is missing, report the error and offer to recreate with defaults.

## Processed State

Track already-processed message IDs in `~/development/gmail-digest/.processed.json`:

```json
{
  "last_run": "2026-03-21T07:00:00Z",
  "processed": {
    "messageId": "YYYY-MM-DD"
  }
}
```

If `.processed.json` doesn't exist, create it with `{"last_run": null, "processed": {}}`. If malformed (unparseable JSON or missing required keys), recreate it with `{"last_run": null, "processed": {}}`.

On each run: prune `processed` entries with dates older than 30 days from today. Also prune files in `~/development/gmail-digest/messages/` with dates older than 30 days (based on the date prefix in the filename).

## Execution Steps

### Step 1: Load config

Read `~/development/gmail-digest/config.json`. If missing, create with defaults above. Validate required fields `labels` and `timezone` are present; if not, report and offer to recreate.

### Step 2: Load processed state

Read `~/development/gmail-digest/.processed.json`. Create empty if missing. Recreate empty if malformed. Prune `processed` entries older than 30 days. Prune `messages/` files older than 30 days.

### Step 3: Search Gmail

**If `$ARGUMENTS` is a sender email:**
- Call `gmail_search_messages` with query `from:$ARGUMENTS is:unread`, maxResults from config.
- Paginate if `nextPageToken` is returned and fewer than `max_results` collected.
- Track source as "Sender Filter".

**Otherwise, fetch three sources in priority order:**

1. **EA-labeled messages** — For each label in `config.labels`:
   - Compute label slug: lowercase, replace spaces with hyphens (e.g., `@action now` → `@action-now`).
   - Call `gmail_search_messages` with query `label:{label-slug} is:unread`, maxResults from config.
   - Paginate if `nextPageToken` is returned and fewer than `max_results` collected.
   - Track source as the label name (e.g., `@action now`).

2. **Other Inbox** — After fetching all labeled messages:
   - Build exclusion clause using all label slugs: `-label:{label1-slug} -label:{label2-slug} ...`
   - Call `gmail_search_messages` with query `in:inbox is:unread {exclusion-clause}`, maxResults from config.
   - Paginate if `nextPageToken` is returned and fewer than `max_results` collected.
   - Track source as "Other Inbox".

Track which source/label each message came from throughout subsequent steps.

### Step 4: Filter

Skip this step entirely if `$ARGUMENTS` (sender filter) was provided.

- EA-labeled items (from any label in `config.labels`) are **never** filtered by `exclude_patterns`.
- `exclude_patterns` apply **only** to Other Inbox messages.
- For Other Inbox messages: exclude if the full `From` header contains any exclude_patterns entry (case-insensitive substring match).

### Step 5: Deduplicate

Remove any messages whose IDs are already present as keys in `.processed.json`'s `processed` object.

### Step 6: If no new messages

Write a brief `~/development/gmail-digest/digests/YYYY-MM-DD-HHmm.md` noting:

```
No new emails since last check at [last_run timestamp, or "the beginning" if null].
```

Update `last_run` to now. Write updated `.processed.json`. Stop.

### Step 7: Fetch and save each message

For each message:

1. Call `gmail_read_message` with the message ID.
2. Extract: subject, from, to, cc, date, body.
3. HTML-only bodies: strip tags. If empty after stripping, use "(No text content)".
4. Truncate body at 10,000 characters, appending "(truncated)" if cut.
5. Note attachments by filename and size; do not download.
6. Slugify subject: lowercase, replace non-alphanumeric characters with hyphens, collapse consecutive hyphens, strip leading/trailing hyphens, truncate to 50 characters.
7. Compute filename: `YYYY-MM-DD-{slug}-{first8charsOfMessageId}.md` using today's date.
8. Write to `~/development/gmail-digest/messages/{filename}` using an atomic write: write to `{filename}.tmp` first, then rename to `{filename}`.

File format:

```markdown
# Subject Line

| Field  | Value |
|--------|-------|
| From   | sender@example.com |
| To     | recipient@example.com |
| CC     | cc@example.com |
| Date   | YYYY-MM-DD HH:MM |
| Label  | @action now |

---

Email body content...
```

- Omit the CC row if CC is empty.
- The Label row shows which source the message came from (label name or "Other Inbox").

After a successful write, add the message ID to the in-memory processed state with today's date as the value.

On write failure: report the error, skip the message, continue with remaining.

### Step 8: Classify each email

Use LLM judgment to assign one classification per email:

- **Action Needed** — expects a response, decision, or approval from the user.
- **Delegatable** — action is needed but could reasonably be handled by the EA or a team member rather than the user directly.
- **FYI** — purely informational; no response expected (notifications, reports, RSVPs, shares).

`@action now` labeled items inherit **Action Needed** by default. Additionally determine whether they are also Delegatable.

### Step 9: Generate draft replies and delegation suggestions

For emails classified as Action Needed or that otherwise invite a response:

- Write in an executive tone: concise, decisive.
- Routine approvals or confirmations: one-liner ready to send as-is.
- Complex topics requiring judgment: 2–3 sentences with `[FILL]` placeholders for unknowns.
- Purely informational alerts: one-line acknowledgment only if a reply would be appropriate.
- Mark draft replies with: `💬 Draft reply:`

For emails classified as Delegatable:

- Coordination or scheduling tasks → suggest forwarding to EA.
- Technical follow-up → suggest forwarding to inferred team lead (use thread participants as signal).
- Mark suggestions with: `🔀 Delegate to:` followed by suggested recipient and a brief forwarding note.

Nothing is sent automatically. All suggestions are advisory only.

### Step 10: Generate digest

Write to `~/development/gmail-digest/digests/YYYY-MM-DD-HHmm.md` using an atomic write (write to `.tmp` first, then rename). The filename uses the current local date and time (e.g., `2026-03-22-0700.md` for the 7am run). This preserves a history of digests rather than overwriting.

The digest has three layers:

---

**Layer 1 — Executive Summary**

```markdown
# Email Digest — YYYY-MM-DD HH:MM

**Since last check:** N new emails | X need your decision | Y delegatable | Z FYI

## What You Need to Know

[Narrative summary: what's time-sensitive, what's been waiting too long, what's resolved, what the overall picture looks like. Written in executive prose, not bullet points. 3–5 sentences.]

**Act on now:** [items with deadlines or aging risk]
**Can delegate:** [items suitable for EA or team]
**Can wait:** [informational items with no time pressure]
```

---

**Layer 2 — Decision Queue and Categorized Detail**

One section per label in `config.labels` order, followed by Other Inbox. Omit a section if it has no messages.

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

---

**Layer 3 — Dashboard**

```markdown
## Dashboard
| Folder      | New | Action Needed | Delegatable | FYI |
|-------------|-----|---------------|-------------|-----|
| @Action Now | N   | N             | N           | N   |
| Calendar    | N   | N             | N           | N   |
| Other Inbox | N   | N             | N           | N   |
| **Total**   | N   | N             | N           | N   |
```

---

The digest shows only the current batch. Each run creates a new file; previous digests are preserved.

### Step 11: Save processed state

Write updated `.processed.json` using atomic write (write to `.processed.json.tmp`, then rename). Include updated `last_run` timestamp (current UTC time in ISO 8601) and the merged `processed` map.

### Step 12: Report results

Tell the user:
- How many emails were fetched in total and per label/source.
- Where the digest file is (`~/development/gmail-digest/digests/YYYY-MM-DD-HHmm.md`).
- How many require action, how many are delegatable, how many are FYI.

## Error Handling

- **MCP tools unavailable**: Report "Gmail MCP tools not available. Ensure you're logged in." Stop immediately.
- **Network failure mid-batch**: Save all messages successfully fetched so far. Update processed state for those messages. Write a partial digest clearly marked as partial. Report partial results to the user.
- **Malformed config.json**: Report the parse error. Validate that `labels` and `timezone` are present. Offer to recreate with defaults.
- **Malformed .processed.json**: Report the error. Recreate with `{"last_run": null, "processed": {}}` and continue.
- **No unread messages**: Write brief digest noting no new mail since last check. Update `last_run`. Stop.
- **File write failure**: Report error for that specific file, skip the message, continue with remaining messages.
- **Atomic writes**: All writes to `.processed.json` and digest files must go through a `.tmp` file first, then rename. Message files in `messages/` also use atomic writes.
