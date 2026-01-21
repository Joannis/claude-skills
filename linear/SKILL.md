---
name: linear
description: 'Linear CLI for issue tracking. Use when developers mention: (1) Linear issues, (2) issue tracking or task management, (3) WDY issues, (4) closing or updating tickets.'
---

# Linear CLI

## Overview

The Linear CLI (`linear`) provides command-line access to Linear issue tracking. Installed via Homebrew at `/opt/homebrew/bin/linear`.

## Required Configuration

Commands require `LINEAR_ISSUE_SORT` to be set:

```bash
export LINEAR_ISSUE_SORT=priority
```

Without this, most commands will fail.

## Team

- **Team Key**: WDY (Wendy)

Use `linear team list` to discover available teams.

## Issue States

| State | Description |
|-------|-------------|
| `triage` | New issues needing triage |
| `backlog` | Prioritized but not started |
| `unstarted` | Ready to start (Todo) |
| `started` | In Progress |
| `completed` | Done |
| `canceled` | Canceled/Won't do |

## Common Commands

### List Issues

```bash
# Active issues (excludes completed/canceled)
LINEAR_ISSUE_SORT=priority linear issue list --team WDY --no-pager

# Filter by state
LINEAR_ISSUE_SORT=priority linear issue list --team WDY --no-pager -s started -s unstarted

# All issues including completed/canceled
LINEAR_ISSUE_SORT=priority linear issue list --team WDY --no-pager --all-states
```

### View Issue

```bash
LINEAR_ISSUE_SORT=priority linear issue view WDY-123 --no-pager
```

### Update Issue Status

```bash
linear issue update WDY-123 --state "Done"
linear issue update WDY-123 --state "In Progress"
```

### Create PR Linked to Issue

```bash
linear issue pr WDY-123
```

### List Teams

```bash
linear team list
```

## Workflows

### Check Issues to Close

```bash
# List active issues
LINEAR_ISSUE_SORT=priority linear issue list --team WDY --no-pager -s started -s unstarted -s backlog

# Cross-reference with recent commits
git log --oneline -30 --all
```

### Triage New Issues

```bash
# View issues in triage
LINEAR_ISSUE_SORT=priority linear issue list --team WDY --no-pager -s triage
```
