---
name: pr
description: Create a pull request with proper description format
argument-hint: "[base-branch]"
user-invocable: true
allowed-tools: Bash, Read
---

Create a pull request following project conventions.

## Pre-PR Checks

1. **Verify branch**: Ensure you're not on main/master
2. **Check commits**: Review all commits to be included
3. **Run verification**: See CLAUDE.md §3 for project-specific verification

## PR Process

1. **Push branch**: `git push -u origin <branch-name>`
2. **Create PR**: Use `gh pr create` with proper format

## PR Description Format

```markdown
## Summary
<1-3 bullet points describing the change>

## Changes
- [List of specific changes]

## Test Plan
- [ ] Unit tests pass
- [ ] Manual verification steps

## Related
- Closes #<issue-number> (if applicable)
- Related to #<issue-number>

---
Generated with [Claude Code](https://claude.com/claude-code)
```

## After PR

Return the PR URL. Do NOT merge unless explicitly requested.
