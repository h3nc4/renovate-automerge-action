# Automerge Renovate pull request

Merges a Renovate pull request the moment CI passes, instead of waiting for Renovate's next scheduled scan to notice the green checks and merge it itself.

Renovate's own `automerge` already does this, but it needs GitHub's native auto-merge to be armable, which requires both "Allow auto-merge" on the repository and a required status check on the target branch. Without those, Renovate falls back to merging on its next run, which is the delay this action removes.

## Usage

The action cannot own the trigger: `workflow_run` is what lets the merge decision run from the default branch, and a reusable trigger is not a thing an action can provide. So each repository keeps a small stub that declares the trigger and grants the permissions.

```yaml
name: Automerge Renovate

on:
  workflow_run:
    workflows:
      - CI # name: of the workflow whose success should merge
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
        with:
          private-key: ${{ secrets.AUTOMERGE_APP_PRIVATE_KEY }}
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

The label is the gate, so the policy for _which_ updates may merge stays in `renovate.json` rather than being restated in CI. Majors are absent from `matchUpdateTypes`, so they never carry the label and never merge unattended. That matters for anything that runs schema migrations on a major upgrade.

## App token

A merge made with the job's `GITHUB_TOKEN` doesn't create new workflow runs, so CI and publish-on-push never fire for the merged bump and nothing rebuilds. Any other credential behaves like a normal push, so the action mints an installation token from a GitHub App.

It does that itself, so the calling workflow doesn't need a token step. Only the private key has to be passed in, because an action cannot read the `secrets` context.

The app id is not a secret. It appears on the app's own settings page, and every JWT the app signs includes it, so `client-id` defaults to the app this action was written for. That leaves one secret and nothing else per repository. Override `client-id` to point it at a different app.

Install the app with **All repositories** and it covers repositories you create later, without collaborator invitations. It needs `Contents: write`, `Pull requests: write` and `Checks: read`.

Passing `token` instead uses that credential and skips the app entirely, for a personal access token. With neither, it falls back to the job token, which merges but triggers nothing.

## Why `workflow_run`

A `pull_request` trigger runs the workflow definition **from the pull request's head**, so a pull request could edit the checks below and merge itself. A `workflow_run` trigger always runs the definition on the default branch.

## What it refuses

Each of these exits successfully with a notice rather than failing, so unrelated pull requests do not show a red check:

- the triggering run was not a `pull_request` run, or did not conclude `success`
- the run was not triggered by the bot (`workflow_run.actor.login`)
- the pull request was not opened by the bot (`author.login`), checked separately so a commit pushed onto a Renovate branch by someone else is not merged under the bot's authorship
- the head repository is not this repository, i.e. a fork
- the pull request does not have the label
- **any commit in the pull request is not authored by the bot, or not signed by GitHub**. This one reports a warning rather than a notice, since it means an otherwise mergeable Renovate pull request was touched
- anything was pushed to the branch after the commit CI tested (`--match-head-commit`)

Both identity checks read GitHub identities, not commit metadata, so they cannot be forged by
setting a commit author. `renovate[bot]` is also unregisterable by a person: `[bot]` is reserved
for GitHub Apps and brackets are not valid in usernames.

## Inputs

| input           | default         | description                                           |
| --------------- | --------------- | ----------------------------------------------------- |
| `client-id`     | the owner's app | App id used to mint a token. Not a secret.            |
| `private-key`   | none            | That app's private key, from a secret.                |
| `token`         | none            | Credential to use instead of an app, such as a PAT.   |
| `label`         | `automerge`     | Label the pull request must have.                     |
| `bot-login`     | `renovate[bot]` | Login that must have opened it and triggered the run. |
| `merge-method`  | `squash`        | `squash`, `merge` or `rebase`.                        |
| `delete-branch` | `true`          | Delete the branch after merging.                      |

## Outputs

| output   | description                                                |
| -------- | ---------------------------------------------------------- |
| `merged` | Merged pull request number, empty when nothing was merged. |

## Requirements

One secret per repository, holding the app's private key. With `token` or the job-token fallback instead, `Settings → Actions → General → Workflow permissions` must allow read and write, or the merge call is refused with a 403.

## License

BSD-2-Clause. See [LICENSE](LICENSE).
