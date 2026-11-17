#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Henrique Almeida <me@h3nc4.com>

# Feeds pending.jq a list of check runs and asserts which ones block the merge.
# Needs jq.

set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
filter="${root}/pending.jq"
cleanup="Delete the shared dev image"

failures=0

runs() { # args: name|status|conclusion, one per check run, printed as a check-runs response
  printf '%s\n' "$@" | jq -Rn '{check_runs: [inputs | split("|")
    | {name: .[0], status: .[1], conclusion: (if .[2] == "" then null else .[2] end)}]}'
}

check() { # $1=label $2=expected, rest: check runs
  label="$1"
  expected="$2"
  shift 2
  if actual="$(runs "$@" | jq -r -f "${filter}")"; then
    if [ "${expected}" = "${actual}" ]; then
      printf '  ok    %s\n' "${label}"
      return 0
    fi
    printf '  FAIL  %s\n          expected %s\n          got      %s\n' \
      "${label}" "${expected:-nothing}" "${actual:-nothing}"
  else
    printf '  ERROR %s\n          jq exited %s\n' "${label}" "$?"
  fi
  failures=$((failures + 1))
}

echo "pending.jq"

check "every check passed" "" \
  "Lint, test and build|completed|success" "CodeQL|completed|success"

check "skipped and neutral pass" "" \
  "Lint, test and build|completed|success" "${cleanup}|completed|skipped" \
  "Sonar|completed|neutral"

check "a failed check blocks" "Lint, test and build is completed/failure" \
  "Lint, test and build|completed|failure" "CodeQL|completed|success"

check "a timed out check blocks" "CodeQL is completed/timed_out" \
  "Lint, test and build|completed|success" "CodeQL|completed|timed_out"

check "a running check blocks" "CodeQL is in_progress/-" \
  "Lint, test and build|completed|success" "CodeQL|in_progress|"

check "a cancelled cleanup blocks" "${cleanup} is completed/cancelled" \
  "Lint, test and build|completed|success" "${cleanup}|completed|cancelled"

check "every blocking check is named on one line" \
  "${cleanup} is completed/cancelled, Gesture end-to-end is completed/failure, SonarQube Scan is completed/cancelled" \
  "${cleanup}|completed|cancelled" "Lint, test and build|completed|success" \
  "Gesture end-to-end|completed|failure" "SonarQube Scan|completed|cancelled"

if [ "${failures}" -ne 0 ]; then
  echo "${failures} failed"
  exit 1
fi
echo "all passed"
