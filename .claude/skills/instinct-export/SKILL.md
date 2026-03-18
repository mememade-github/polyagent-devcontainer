---
name: instinct-export
description: Export personal instincts for sharing. Outputs a portable instinct collection file.
---

# /instinct-export — Export Instincts

Export instincts from `.claude/instincts/personal/` to a portable format for sharing across projects or team members.

## Process

1. Read all instincts in `.claude/instincts/personal/`
2. Filter by minimum confidence (default: 0.5)
3. Combine into export file at `.claude/instincts/export-<date>.md`
4. Report count and domains exported

## Rules

- Only export instincts with confidence >= 0.5
- Never export instincts containing project secrets
