# Automerge Renovate pull request

Merges a Renovate pull request the moment CI passes, instead of waiting for Renovate's next
scheduled scan to notice the green checks and merge it itself.

Renovate's own `automerge` already does this, but it needs GitHub's native auto-merge to be
armable, which requires both "Allow auto-merge" on the repository and a required status check on
the target branch. Without those, Renovate falls back to merging on its next run — the delay this
action removes.

## Usage

The action cannot own the trigger: `workflow_run` is what lets the merge decision run from the
default branch, and a reusable trigger is not a thing an action can provide. So each repository
keeps a small stub that owns the trigger and grants the permissions.

```yaml
name: Automerge Renovate

on:
  workflow_run:
    workflows:
      - CI          # name: of the workflow whose success should merge
    types:
      - completed

permissions: {}

jobs:
  automerge:
    name: Merge if CI passed
    # Evaluated before a runner is allocated, so a run that cannot lead to a merge costs
    # nothing. Check the event too: CI usually also runs on pushes to the default branch, and
    # without it every push boots a runner just to skip. The action re-checks both anyway.
    if: >-
      github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.event == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: h3nc4/renovate-automerge-action@v1
```

Then label the updates that may merge, from `renovate.json`:

```json
{
  "packageRules": [
    {
      "matchUpdateTypes": ["minor", "patch", "pin", "digest"],
      "automerge": true,
      "platformAutomerge": true,
      "addLabels": ["automerge"]
    }
  ]
}
```

The label is the gate, so the policy for *which* updates may merge stays in `renovate.json`
rather than being restated in CI. Majors are absent from `matchUpdateTypes`, so they never carry
the label and never merge unattended — which matters for anything that runs schema migrations on
a major upgrade.

## Why `workflow_run`

A `pull_request` trigger runs the workflow definition **from the pull request's head**, so a pull
request could edit the checks below and merge itself. A `workflow_run` trigger always runs the
definition on the default branch.

## What it refuses

Each of these exits successfully with a notice rather than failing, so unrelated pull requests do
not show a red check:

- the triggering run was not a `pull_request` run, or did not conclude `success`
- the run was not triggered by the bot (`workflow_run.actor.login`)
- the pull request was not opened by the bot (`author.login`) — checked separately, so a commit
  pushed onto a Renovate branch by someone else cannot ride along on the bot's authorship
- the head repository is not this repository, i.e. a fork
- the pull request does not carry the label
- **any commit in the pull request is not authored by the bot, or not signed by GitHub** — this
  one is reported as a warning rather than a notice, since it means an otherwise mergeable
  Renovate pull request was touched
- anything landed on the branch after the commit CI tested (`--match-head-commit`)

Both identity checks read GitHub identities, not commit metadata, so they cannot be forged by
setting a commit author. `renovate[bot]` is also unregisterable by a person: `[bot]` is reserved
for GitHub Apps and brackets are not valid in usernames.

## Inputs

| input           | default               | description                                           |
| --------------- | --------------------- | ----------------------------------------------------- |
| `label`         | `automerge`           | Label the pull request must carry.                    |
| `bot-login`     | `renovate[bot]`       | Login that must have opened it and triggered the run. |
| `merge-method`  | `squash`              | `squash`, `merge` or `rebase`.                        |
| `delete-branch` | `true`                | Delete the branch after merging.                      |
| `token`         | `${{ github.token }}` | Needs `contents:write` and `pull-requests:write`.     |

## Outputs

| output   | description                                                |
| -------- | ---------------------------------------------------------- |
| `merged` | Merged pull request number, empty when nothing was merged. |

## Requirements

`Settings → Actions → General → Workflow permissions` must allow read and write, or the merge
call is refused with a 403.

## License

BSD-2-Clause. See [LICENSE](LICENSE).
