# Project Workflow

## Issue First

Create or identify a GitHub issue before starting tracked work. Use a dedicated branch named `<issue-label>/<issue-number>`, such as `documentation/33`, and open a pull request after verification.

## Stacked Pull Requests

Pull requests must form a single chain, never a fan-out from `main`. Before creating a branch, check for open pull requests:

```bash
gh pr list --state open --json number,headRefName,baseRefName
```

- No open pull request: branch from `main` and use `--base main`.
- One or more open pull requests: find the tip of the chain, which is the open pull request whose `headRefName` is not the `baseRefName` of any other open pull request. Branch from that pull request's head branch and pass it as `--base`.

Only one pull request may target `main` at a time. Every other open pull request targets the branch directly below it in the stack.

After a pull request in the stack merges, rebase the branch above it and confirm its base still points at the correct branch; GitHub retargets it to `main` when the base branch is deleted.

This is what keeps the ordering check in `scripts/ci/validate-migrations.sh` meaningful. That check rejects a migration numbered at or below the highest version on the base branch, but the result is only as current as the base branch was when the job ran. Two pull requests opened from `main` at the same time both pass; GitHub does not re-run the `pull_request` workflow when the base branch moves, so after one merges the other can still merge a lower version with a green check. Stacking keeps every open pull request compared against the highest published version.

## Metadata

Every issue and pull request must set an assignee and a label. Do not leave either blank.

- Assignee: `--assignee @me`.
- Label: use the same value as the branch prefix. Check available labels with `gh label list`; do not invent a new label when none fit.
- Do not attach a project.
- When GitHub CLI authentication appears invalid inside a sandbox but the user says their session is valid, request escalated execution and retry `gh` with the user's session credentials before asking them to re-authenticate.

```bash
gh issue create --title "..." --body "..." --assignee @me --label documentation
gh pr create --base <base> --title "..." --body "..." --assignee @me --label documentation
```

Confirm the metadata after creation:

```bash
gh issue view <issue-number> --json assignees,labels
gh pr view <pr-number> --json assignees,labels
```
