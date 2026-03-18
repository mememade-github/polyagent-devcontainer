---
name: instinct-import
description: Import instincts from external sources. Places them in inherited/ directory with source tracking.
user-invocable: true
---

# /instinct-import — Import Instincts

Import instincts from an export file into `.claude/instincts/inherited/`.

## Usage

`/instinct-import <file-path>`

## Process

1. Read the export file
2. Validate each instinct has required fields (id, trigger, confidence, domain)
3. Place in `.claude/instincts/inherited/` with `source: "imported"` tag
4. Reduce confidence by 0.1 (imported instincts start slightly lower)
5. Report count imported and any duplicates skipped

## Rules

- Imported instincts go to `inherited/` not `personal/`
- If instinct ID conflicts with existing, keep higher confidence
- Add source tracking (import date, source file)
